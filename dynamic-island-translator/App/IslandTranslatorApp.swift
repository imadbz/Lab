import AppIntents
import SwiftUI
import Translation

@main
struct IslandTranslatorApp: App {
    @ObservedObject private var model = LabModel.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var model: LabModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView(selection: $model.tab) {
            TranslateView()
                .tabItem { Label("Translate", systemImage: "character.bubble") }
                .tag(LabTab.translate)
            ScreenView()
                .tabItem { Label("Screen", systemImage: "camera.viewfinder") }
                .tag(LabTab.screen)
            FitLabView()
                .tabItem { Label("Fit Lab", systemImage: "ruler") }
                .tag(LabTab.fit)
            LogView()
                .tabItem { Label("Log", systemImage: "list.bullet.rectangle") }
                .tag(LabTab.log)
        }
        .translationTask(model.translationConfig) { session in
            await model.runPending(with: session)
        }
        .onOpenURL { model.handle(url: $0) }
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                model.syncFromIsland()
                Task { await model.resumeScreenReading() }
            }
        }
    }
}

// MARK: - Shortcuts / Action button

/// Copy a foreign message anywhere → run this (Action button, Back Tap, Siri) → translation lands in the island.
struct TranslateClipboardIntent: AppIntent {
    static let title: LocalizedStringResource = "Translate Clipboard"
    static let description = IntentDescription("Translates the copied text and shows it in the Dynamic Island.")
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        LabModel.shared.translateClipboard()
        return .result()
    }
}

struct IslandShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: TranslateClipboardIntent(),
            phrases: ["Translate clipboard with \(.applicationName)"],
            shortTitle: "Translate Clipboard",
            systemImageName: "doc.on.clipboard"
        )
    }
}
