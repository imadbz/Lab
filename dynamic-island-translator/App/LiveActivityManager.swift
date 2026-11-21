import ActivityKit
import Foundation

enum IslandError: LocalizedError {
    case disabled

    var errorDescription: String? {
        "Live Activities are turned off for this app (Settings › Island Translator › Live Activities)."
    }
}

/// Thin wrapper around ActivityKit: start, update (optionally with an alert that pops the island open), end.
@MainActor
final class LiveActivityManager {
    typealias State = TranslatorAttributes.ContentState

    var current: Activity<TranslatorAttributes>? {
        Activity<TranslatorAttributes>.activities.first {
            $0.activityState == .active || $0.activityState == .stale
        }
    }

    /// Returns `true` if a new activity was started, `false` if an existing one was updated.
    func push(_ state: State, chatName: String, alert: Bool) async throws -> Bool {
        let content = ActivityContent(
            state: state,
            staleDate: Date().addingTimeInterval(60 * 60),
            relevanceScore: 100
        )

        if let activity = current {
            if alert {
                // An alert update briefly shows the EXPANDED island (and lights up the screen on device)
                // without the user long-pressing — this is how a new incoming translation "pops".
                let config = AlertConfiguration(
                    title: LocalizedStringResource(stringLiteral: "\(Lang.flag(state.sourceLang)) \(chatName)"),
                    body: LocalizedStringResource(stringLiteral: state.translated),
                    sound: .default
                )
                await activity.update(content, alertConfiguration: config)
            } else {
                await activity.update(content)
            }
            return false
        }

        guard ActivityAuthorizationInfo().areActivitiesEnabled else { throw IslandError.disabled }
        _ = try Activity<TranslatorAttributes>.request(
            attributes: TranslatorAttributes(chatName: chatName),
            content: content,
            pushType: nil // set to .token later to drive the island from a server via APNs
        )
        return true
    }

    func endAll() async {
        for activity in Activity<TranslatorAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
