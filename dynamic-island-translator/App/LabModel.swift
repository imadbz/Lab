import ActivityKit
import Foundation
import NaturalLanguage
import SwiftUI
import Translation
import UIKit

enum LabTab: Hashable {
    case translate, screen, fit, log
}

struct ChatMessage: Identifiable {
    let id = UUID()
    let original: String
    let translated: String
    let src: String
    let tgt: String
    let incoming: Bool
}

struct LogLine: Identifiable {
    let id = UUID()
    let text: String
}

private struct TranslationJob {
    let text: String
    let src: String
    let tgt: String
    let incoming: Bool
}

@MainActor
final class LabModel: ObservableObject {
    static let shared = LabModel()

    @Published var tab: LabTab = .screen // the zero-setup screen reader is the way in
    // Persisted so a Shortcut running in the background (fresh process) sees the same settings.
    @Published var chatName = UserDefaults.standard.string(forKey: "chatName") ?? "Sofía" {
        didSet { UserDefaults.standard.set(chatName, forKey: "chatName") }
    }
    @Published var theirLang = UserDefaults.standard.string(forKey: "theirLang") ?? "es" {
        didSet { UserDefaults.standard.set(theirLang, forKey: "theirLang") }
    }
    @Published var myLang = UserDefaults.standard.string(forKey: "myLang") ?? "en" {
        didSet { UserDefaults.standard.set(myLang, forKey: "myLang") }
    }
    @Published var apiKey = Keychain.apiKey ?? "" {
        didSet { Keychain.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines) }
    }
    @Published var readerMode: ReaderMode = (Keychain.apiKey ?? "").isEmpty ? .onDevice : .claude
    @Published var screenBusy = false
    @Published var screenResult: ScreenResult?
    @Published var screenError: String?
    @Published var input = ""
    @Published var incoming = true
    @Published var engine: Engine = .preferred
    @Published var popWithAlert = true
    @Published var lab = LabOptions()
    @Published var history: [ChatMessage] = []
    @Published var logLines: [LogLine] = []
    @Published var islandActive = false
    @Published var focusInput = false
    @Published private(set) var lastState: TranslatorAttributes.ContentState?

    /// Driving this re-runs the `.translationTask` attached in ContentView.
    @Published var translationConfig: TranslationSession.Configuration?

    private var configKey = ""
    private var pending: TranslationJob?
    private var pendingContinuation: CheckedContinuation<String, Never>?
    private var demoTask: Task<Void, Never>?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private let island = LiveActivityManager()
    private let keepAlive = KeepAlive()
    private var autoTask: Task<Void, Never>?
    private var lastAutoSignature: [UInt8]?
    private var lastAutoText: String?
    private var lastActiveAt = Date()
    @Published var autoTranslating = false

    private var key: String { apiKey.trimmingCharacters(in: .whitespacesAndNewlines) }

    var lastStateBytes: Int {
        guard let lastState, let data = try? JSONEncoder().encode(lastState) else { return 0 }
        return data.count
    }

    // MARK: Translate

    func translateInput() {
        translate(input, incoming: incoming)
    }

    func translateClipboard() {
        tab = .translate
        guard let text = UIPasteboard.general.string, !text.isEmpty else {
            log("Clipboard is empty")
            return
        }
        input = text
        incoming = true
        translate(text, incoming: true)
    }

    func translate(_ raw: String, incoming: Bool) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let src = incoming ? theirLang : myLang
        let tgt = incoming ? myLang : theirLang
        guard src != tgt else {
            log("Pick two different languages")
            return
        }
        Task {
            let out = await translateText(text, from: src, to: tgt)
            await deliver(original: text, translated: out, src: src, tgt: tgt, incoming: incoming)
        }
    }

    /// One entry point for every engine. Never throws: falls back to the mock so the island always updates.
    func translateText(_ text: String, from src: String, to tgt: String) async -> String {
        switch engine {
        case .mock:
            return MockTranslator.translate(text, from: src, to: tgt)

        case .claude:
            guard !key.isEmpty else {
                log("No API key — using mock")
                return MockTranslator.translate(text, from: src, to: tgt)
            }
            do {
                return try await ClaudeClient.translate(text, from: src, to: tgt, apiKey: key)
            } catch {
                log("Claude translate failed: \(error.localizedDescription)")
                return MockTranslator.translate(text, from: src, to: tgt)
            }

        case .apple:
            #if compiler(>=6.2)
            // iOS 26+: a session that works with no UI — i.e. from a background Shortcut —
            // as long as both languages are already downloaded.
            if #available(iOS 26.0, *) {
                do {
                    let session = TranslationSession(installedSource: Locale.Language(identifier: src),
                                                     target: Locale.Language(identifier: tgt))
                    return try await session.translate(text).targetText
                } catch {
                    log("Languages not installed for background use (\(error.localizedDescription))")
                }
            }
            #endif
            if UIApplication.shared.applicationState == .active {
                return await translateViaTask(text, from: src, to: tgt)
            }
            log("Open the app once to download \(src)→\(tgt) — using mock for now")
            return MockTranslator.translate(text, from: src, to: tgt)
        }
    }

    /// Bridges SwiftUI's `.translationTask` (which can show the language-download sheet) to async/await.
    private func translateViaTask(_ text: String, from src: String, to tgt: String) async -> String {
        if let stale = pendingContinuation, let job = pending {
            stale.resume(returning: MockTranslator.translate(job.text, from: job.src, to: job.tgt))
        }
        return await withCheckedContinuation { continuation in
            pendingContinuation = continuation
            pending = TranslationJob(text: text, src: src, tgt: tgt, incoming: true)
            let key = "\(src)>\(tgt)"
            if key == configKey, translationConfig != nil {
                translationConfig?.invalidate()
            } else {
                configKey = key
                translationConfig = TranslationSession.Configuration(
                    source: Locale.Language(identifier: src),
                    target: Locale.Language(identifier: tgt)
                )
            }
        }
    }

    /// Called from `.translationTask` — the session is only valid inside that closure.
    func runPending(with session: TranslationSession) async {
        guard let job = pending, let continuation = pendingContinuation else { return }
        pending = nil
        pendingContinuation = nil
        do {
            continuation.resume(returning: try await session.translate(job.text).targetText)
        } catch {
            log("Apple Translation failed (\(error.localizedDescription)) — using mock")
            continuation.resume(returning: MockTranslator.translate(job.text, from: job.src, to: job.tgt))
        }
    }

    private func deliver(original: String, translated: String, src: String, tgt: String,
                         incoming: Bool, chat: String? = nil,
                         replies: [SuggestedReply] = [], note: String = "") async {
        history.insert(ChatMessage(original: original, translated: translated,
                                   src: src, tgt: tgt, incoming: incoming), at: 0)
        let unread = incoming ? (lastState?.unread ?? 0) + 1 : 0
        let state = TranslatorAttributes.ContentState(
            original: original, translated: translated,
            sourceLang: src, targetLang: tgt,
            incoming: incoming, unread: unread,
            updatedAt: Date(), lab: lab,
            replies: replies, note: note
        )
        await push(state, alert: popWithAlert && incoming, chat: chat)
    }

    // MARK: Screenshots

    /// UI entry point (photo picker / "latest screenshot" button).
    func processScreen(_ image: UIImage) {
        Task {
            do {
                _ = try await readScreen(image, mode: readerMode)
            } catch {
                screenError = error.localizedDescription
                log("Screen read failed: \(error.localizedDescription)")
            }
        }
    }

    func processLatestScreenshot() {
        Task {
            do {
                processScreen(try await ScreenImages.latestScreenshot())
            } catch {
                screenError = error.localizedDescription
            }
        }
    }

    // MARK: Live screen

    /// "Start" in the app: put the island up now, while the app is in front (iOS starts
    /// Live Activities only from the foreground), so its "Translate screen" button is there later.
    func prepareScreenIsland() async {
        guard island.current == nil else { return }
        let waiting = TranslatorAttributes.ContentState(
            original: "Screen sharing", translated: "Watching for new messages",
            sourceLang: theirLang, targetLang: myLang,
            incoming: true, unread: 0, updatedAt: Date(), lab: lab
        )
        await push(waiting, alert: false)
    }

    /// The island's "Translate screen" button. Runs in the app, often launched in the background for it.
    func translateLiveScreen() async {
        do {
            // Take the frame first: it's from about a second ago, before the island opened over the chat.
            guard let jpeg = ScreenShare.latestFrame(), let image = UIImage(data: jpeg) else {
                throw ScreenError.notSharing
            }
            if var reading = island.current?.content.state ?? lastState {
                reading.busy = true
                await push(reading, alert: false)
            }
            _ = try await readScreen(image, mode: readerMode)
        } catch {
            log("Translate screen failed: \(error.localizedDescription)")
            // The island is the only place the person is looking, so the reason goes there.
            guard var state = island.current?.content.state ?? lastState else { return }
            state.busy = false
            state.original = "Couldn't translate the screen"
            state.translated = error.localizedDescription
            state.note = ""
            state.replies = []
            state.updatedAt = Date()
            await push(state, alert: false)
        }
    }

    // MARK: Auto-translate

    /// While screen sharing is on, translate each new message from them without a tap.
    /// The app stays running in the background (KeepAlive) and checks the latest frame every
    /// 1.5 s; it runs OCR only when the picture changed, and updates the island only when the
    /// latest message from them is a new one. It stops by itself 60 s after frames stop coming.
    func startAutoTranslate() {
        guard autoTask == nil else { return }
        keepAlive.start()
        autoTranslating = true
        lastAutoSignature = nil
        lastAutoText = nil
        log("Auto-translate on")
        autoTask = Task { [weak self] in
            var quietSince: Date?
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.5))
                guard let self else { return }
                if let jpeg = ScreenShare.latestFrame(), let image = UIImage(data: jpeg) {
                    quietSince = nil
                    await self.autoCheck(image)
                } else {
                    let since = quietSince ?? Date()
                    quietSince = since
                    if Date().timeIntervalSince(since) > 60 { break }
                }
            }
            self?.stopAutoTranslate()
        }
    }

    /// Opening the app while frames are arriving (sharing is on) brings the island and
    /// auto-translate back, e.g. after iOS ended the activity or auto-translate timed out.
    func resumeScreenReading() async {
        guard ScreenShare.isSharing else { return }
        await prepareScreenIsland()
        startAutoTranslate()
    }

    func stopAutoTranslate() {
        autoTask?.cancel()
        autoTask = nil
        keepAlive.stop()
        if autoTranslating { log("Auto-translate off") }
        autoTranslating = false
    }

    private func autoCheck(_ image: UIImage) async {
        // While this app is in front, the frame is this app; there's no chat to read. Frames lag
        // about a second, so the first ones after leaving the app still show it: skip those too.
        if UIApplication.shared.applicationState == .active {
            lastActiveAt = Date()
            lastAutoSignature = nil
            return
        }
        guard Date().timeIntervalSince(lastActiveAt) > 3 else { return }
        guard let cgImage = image.cgImage else { return }
        let signature = ScreenChange.signature(cgImage)
        if let last = lastAutoSignature, ScreenChange.difference(last, signature) < 0.004 { return }
        lastAutoSignature = signature

        guard let messages = try? await ScreenOCR.messages(in: image),
              let latest = messages.last(where: { $0.speaker == .them }) else { return }
        let text = latest.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text != lastAutoText else { return }
        lastAutoText = text

        switch readerMode {
        case .claude:
            // OCR found a new message; only now is it worth a Claude call on the whole screen.
            _ = try? await readScreen(image, mode: .claude)
        case .onDevice:
            let src = Self.languageOf(text) ?? theirLang
            guard src != myLang else { return } // already in my language
            let translated = await translateText(text, from: src, to: myLang)
            log("Auto-translated a new message")
            await deliver(original: text, translated: translated, src: src, tgt: myLang, incoming: true)
        }
    }

    /// Screenshot → messages → translation → island. Shared by the app UI and the Shortcuts action.
    func readScreen(_ image: UIImage, mode: ReaderMode) async throws -> ScreenResult {
        screenBusy = true
        screenError = nil
        defer { screenBusy = false }
        let start = Date()
        var result: ScreenResult

        switch mode {
        case .claude:
            guard !key.isEmpty else { throw ScreenError.noAPIKey }
            let reading = try await ClaudeClient.readScreenshot(image, myLanguage: myLang, apiKey: key)
            let messages = reading.messages.map {
                ScreenMessage(speaker: $0.from == "me" ? .me : .them, text: $0.original, translation: $0.translation)
            }
            guard let latest = reading.messages.last(where: { $0.from == "them" }) ?? reading.messages.last else {
                throw ScreenError.noText
            }
            result = ScreenResult(
                mode: .claude, messages: messages,
                latestOriginal: latest.original, latestTranslation: latest.translation,
                theirLang: reading.theirLanguage,
                contact: reading.contact.isEmpty ? nil : reading.contact,
                note: reading.note,
                replies: reading.suggestedReplies.prefix(3).map { SuggestedReply(text: $0.text, meaning: $0.meaning) },
                thumbnail: ScreenImages.thumbnail(image)
            )

        case .onDevice:
            let messages = try await ScreenOCR.messages(in: image)
            guard let latest = messages.last(where: { $0.speaker == .them }) ?? messages.last else {
                throw ScreenError.noText
            }
            // Their language comes from the message itself; the setting is only the fallback.
            let src = Self.languageOf(latest.text) ?? theirLang
            let translated = await translateText(latest.text, from: src, to: myLang)
            result = ScreenResult(
                mode: .onDevice, messages: messages,
                latestOriginal: latest.text, latestTranslation: translated,
                theirLang: src, contact: nil, note: "", replies: [],
                thumbnail: ScreenImages.thumbnail(image)
            )
        }

        result.elapsed = Date().timeIntervalSince(start)
        screenResult = result
        log("\(mode.label) read \(result.messages.count) messages in \(String(format: "%.1f", result.elapsed)) s")
        await deliver(original: result.latestOriginal, translated: result.latestTranslation,
                      src: result.theirLang, tgt: myLang, incoming: true,
                      chat: result.contact, replies: result.replies, note: result.note)
        return result
    }

    /// The language a message is written in, when the guess is reasonably sure (BCP-47 code, e.g. "fr").
    static func languageOf(_ text: String) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let (language, confidence) = recognizer.languageHypotheses(withMaximum: 1).first,
              confidence >= 0.5 else { return nil }
        return language.rawValue
    }

    // MARK: Island

    private func push(_ state: TranslatorAttributes.ContentState, alert: Bool, chat: String? = nil) async {
        lastState = state
        do {
            let started = try await island.push(state, chatName: chat ?? chatName, alert: alert)
            log(started ? "Started Live Activity" : (alert ? "Updated island + alert" : "Updated island"))
        } catch {
            log("Live Activity error: \(error.localizedDescription)")
        }
        islandActive = island.current != nil
    }

    func pushFitTest(_ text: String, lang: String) {
        let state = TranslatorAttributes.ContentState(
            original: "Fit test · \(text.count) chars", translated: text,
            sourceLang: theirLang, targetLang: lang,
            incoming: true, unread: 1, updatedAt: Date(), lab: lab
        )
        Task { await push(state, alert: popWithAlert) }
    }

    /// What the Claude reader's result looks like in the island (note + reply chips), without an API key.
    func pushAIFitTest() {
        let state = TranslatorAttributes.ContentState(
            original: "Vale. Ah, ¿puedes traerme el cargador que te dejé? El mío se murió anoche.",
            translated: "OK. Oh, can you bring me the charger I left with you? Mine died last night.",
            sourceLang: "es", targetLang: myLang,
            incoming: true, unread: 1, updatedAt: Date(), lab: lab,
            replies: [
                SuggestedReply(text: "¡Claro, lo llevo!", meaning: "Sure, I'll bring it!"),
                SuggestedReply(text: "¿Cuál cargador?", meaning: "Which charger?"),
                SuggestedReply(text: "Ya lo tengo 👍", meaning: "Got it already"),
            ],
            note: "Casual and friendly; \"se murió\" means the battery died."
        )
        Task { await push(state, alert: popWithAlert) }
    }

    /// Re-render the current island with new layout options (no alert).
    func relayout() {
        guard islandActive, var state = lastState else { return }
        state.lab = lab
        Task { await push(state, alert: false) }
    }

    func endIsland() {
        demoTask?.cancel()
        Task {
            await island.endAll()
            islandActive = false
            lastState = nil
            log("Ended Live Activity")
        }
    }

    /// Island buttons (Copy/Flip/End) change the activity behind our back — pick that up on return.
    func syncFromIsland() {
        let current = island.current
        islandActive = current != nil
        if let current { lastState = current.content.state }
    }

    // MARK: Demo

    func runDemo() {
        demoTask?.cancel()
        theirLang = Demo.theirs
        myLang = Demo.mine
        // Ask for ~30 s of background time so the demo keeps going after you swipe home.
        endBackgroundTask()
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "IslandDemo") { [weak self] in
            Task { @MainActor in self?.endBackgroundTask() }
        }
        log("Demo starting — swipe up to Home now!")
        demoTask = Task {
            await island.endAll()
            lastState = nil
            // Live Activities can only be STARTED while the app is in the foreground,
            // so start it now with a placeholder; updates are allowed from the background.
            let waiting = TranslatorAttributes.ContentState(
                original: "Waiting for messages…", translated: "Listening for \(Demo.chatName)",
                sourceLang: Demo.theirs, targetLang: Demo.mine,
                incoming: true, unread: 0, updatedAt: Date(), lab: lab
            )
            await push(waiting, alert: false, chat: Demo.chatName)
            try? await Task.sleep(for: .seconds(3))
            for line in Demo.script {
                if Task.isCancelled { break }
                let src = line.incoming ? Demo.theirs : Demo.mine
                let tgt = line.incoming ? Demo.mine : Demo.theirs
                await deliver(original: line.original, translated: line.translated,
                              src: src, tgt: tgt, incoming: line.incoming, chat: Demo.chatName)
                try? await Task.sleep(for: .seconds(line.pause))
            }
            log("Demo finished")
            endBackgroundTask()
        }
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    // MARK: Misc

    func handle(url: URL) {
        guard url.host == "reply" else { return }
        tab = .translate
        incoming = false
        input = ""
        focusInput = true
        log("Opened from island › Reply")
    }

    func log(_ message: String) {
        let time = Date().formatted(date: .omitted, time: .standard)
        logLines.insert(LogLine(text: "\(time)  \(message)"), at: 0)
    }

    func clearLog() {
        logLines.removeAll()
    }
}
