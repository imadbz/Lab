import ActivityKit
import Foundation
import SwiftUI
import Translation
import UIKit

enum LabTab: Hashable {
    case translate, fit, log
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

    @Published var tab: LabTab = .translate
    @Published var chatName = "Sofía"
    @Published var theirLang = "es"
    @Published var myLang = "en"
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
    private var demoTask: Task<Void, Never>?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private let island = LiveActivityManager()

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

        switch engine {
        case .mock:
            let out = MockTranslator.translate(text, from: src, to: tgt)
            Task { await deliver(original: text, translated: out, src: src, tgt: tgt, incoming: incoming) }
        case .apple:
            pending = TranslationJob(text: text, src: src, tgt: tgt, incoming: incoming)
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
        guard let job = pending else { return }
        pending = nil
        do {
            let response = try await session.translate(job.text)
            await deliver(original: job.text, translated: response.targetText,
                          src: job.src, tgt: job.tgt, incoming: job.incoming)
        } catch {
            log("Apple Translation failed (\(error.localizedDescription)) — using mock")
            await deliver(original: job.text,
                          translated: MockTranslator.translate(job.text, from: job.src, to: job.tgt),
                          src: job.src, tgt: job.tgt, incoming: job.incoming)
        }
    }

    private func deliver(original: String, translated: String, src: String, tgt: String,
                         incoming: Bool, chat: String? = nil) async {
        history.insert(ChatMessage(original: original, translated: translated,
                                   src: src, tgt: tgt, incoming: incoming), at: 0)
        let unread = incoming ? (lastState?.unread ?? 0) + 1 : 0
        let state = TranslatorAttributes.ContentState(
            original: original, translated: translated,
            sourceLang: src, targetLang: tgt,
            incoming: incoming, unread: unread,
            updatedAt: Date(), lab: lab
        )
        await push(state, alert: popWithAlert && incoming, chat: chat)
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
