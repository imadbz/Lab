import ActivityKit
import AppIntents
import UIKit

// Buttons inside the Dynamic Island / Lock Screen (iOS 17+).
// LiveActivityIntent.perform() runs in the APP's process (launched in the background if needed),
// so it can touch the pasteboard and ActivityKit without opening the app.

struct CopyTranslationIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Copy translation"

    func perform() async throws -> some IntentResult {
        if let activity = Activity<TranslatorAttributes>.activities.first {
            UIPasteboard.general.string = activity.content.state.translated
            var state = activity.content.state
            state.unread = 0
            await activity.update(ActivityContent(state: state, staleDate: activity.content.staleDate))
        }
        return .result()
    }
}

/// Swaps which side is shown big: translation ⇄ original.
struct FlipIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Flip original and translation"

    func perform() async throws -> some IntentResult {
        if let activity = Activity<TranslatorAttributes>.activities.first {
            var s = activity.content.state
            (s.original, s.translated) = (s.translated, s.original)
            (s.sourceLang, s.targetLang) = (s.targetLang, s.sourceLang)
            await activity.update(ActivityContent(state: s, staleDate: activity.content.staleDate))
        }
        return .result()
    }
}

struct EndIslandIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "End translator"

    func perform() async throws -> some IntentResult {
        for activity in Activity<TranslatorAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        return .result()
    }
}
