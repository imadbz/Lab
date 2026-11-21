import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct IslandWidgetBundle: WidgetBundle {
    var body: some Widget {
        TranslatorLiveActivity()
    }
}

struct TranslatorLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TranslatorAttributes.self) { context in
            // Lock Screen / notification banner presentation
            LockScreenView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.85))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                // EXPANDED — shown on long-press, or briefly on an alert update.
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 4) {
                        Text(Lang.flag(context.state.sourceLang))
                        Image(systemName: "arrow.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(Lang.flag(context.state.targetLang))
                    }
                    .font(.title3)
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.updatedAt, style: .time)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.chatName)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ExpandedBottom(state: context.state)
                }
            } compactLeading: {
                // COMPACT — the resting state, either side of the camera.
                CompactLeading(state: context.state)
            } compactTrailing: {
                CompactTrailing(state: context.state)
            } minimal: {
                // MINIMAL — when another app's Live Activity is also running.
                Text(Lang.flag(context.state.sourceLang))
            }
            .widgetURL(URL(string: "islandtranslator://open"))
            .keylineTint(.cyan)
        }
    }
}

// MARK: - Compact

struct CompactLeading: View {
    let state: TranslatorAttributes.ContentState

    var body: some View {
        switch state.lab.compactStyle {
        case .flags, .snippet:
            Text(Lang.flag(state.sourceLang))
        case .codes:
            Text("\(Lang.short(state.sourceLang))›\(Lang.short(state.targetLang))")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.cyan)
        }
    }
}

struct CompactTrailing: View {
    let state: TranslatorAttributes.ContentState

    var body: some View {
        switch state.lab.compactStyle {
        case .snippet:
            // Deliberately unconstrained: see how much text the system lets through.
            Text(state.translated)
                .font(.caption2)
                .lineLimit(1)
        case .flags, .codes:
            if state.unread > 0 {
                Text("\(state.unread)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.cyan))
            } else {
                Image(systemName: state.incoming ? "text.bubble.fill" : "paperplane.fill")
                    .foregroundStyle(.cyan)
            }
        }
    }
}

// MARK: - Expanded

struct ExpandedBottom: View {
    let state: TranslatorAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !state.note.isEmpty {
                // AI flow: the nuance beats the original text for the one spare line.
                Label(state.note, systemImage: "lightbulb")
                    .font(.caption)
                    .foregroundStyle(.yellow)
                    .lineLimit(1)
            } else if state.lab.showOriginal {
                Text(state.original)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(state.translated)
                .font(.body.weight(.semibold))
                // Leave room for the reply chips when there are any (expanded height tops out ~160 pt).
                .lineLimit(state.replies.isEmpty ? state.lab.lineLimit : min(state.lab.lineLimit, 2))
                .minimumScaleFactor(state.lab.shrinkToFit ? 0.6 : 1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if state.replies.isEmpty {
                IslandButtons()
            } else {
                ReplyChips(replies: state.replies)
            }
        }
    }
}

/// Tap a chip → that reply (in their language) is on the clipboard, ready to paste into the chat.
struct ReplyChips: View {
    let replies: [SuggestedReply]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(replies.prefix(2).enumerated()), id: \.offset) { index, reply in
                Button(intent: CopyReplyIntent(index: index)) {
                    Text(reply.text).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Button(intent: EndIslandIntent()) {
                Image(systemName: "xmark")
            }
        }
        .font(.caption.weight(.semibold))
        .buttonStyle(.bordered)
        .tint(.cyan)
    }
}

struct IslandButtons: View {
    var body: some View {
        HStack(spacing: 8) {
            Button(intent: CopyTranslationIntent()) {
                Label("Copy", systemImage: "doc.on.doc")
            }
            Button(intent: FlipIntent()) {
                Label("Flip", systemImage: "arrow.left.arrow.right")
            }
            Link(destination: URL(string: "islandtranslator://reply")!) {
                Label("Reply", systemImage: "arrowshape.turn.up.left")
            }
            Spacer(minLength: 0)
            Button(intent: EndIslandIntent()) {
                Image(systemName: "xmark")
            }
        }
        .font(.caption.weight(.semibold))
        .buttonStyle(.bordered)
        .tint(.cyan)
    }
}

// MARK: - Lock Screen

struct LockScreenView: View {
    let context: ActivityViewContext<TranslatorAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(Lang.flag(context.state.sourceLang)) → \(Lang.flag(context.state.targetLang))")
                Text(context.attributes.chatName)
                    .font(.caption.weight(.bold))
                Spacer()
                Text(context.state.updatedAt, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if context.state.lab.showOriginal {
                Text(context.state.original)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Text(context.state.translated)
                .font(.headline)
                .lineLimit(context.state.lab.lineLimit)
                .minimumScaleFactor(context.state.lab.shrinkToFit ? 0.6 : 1)
            if !context.state.note.isEmpty {
                Label(context.state.note, systemImage: "lightbulb")
                    .font(.caption)
                    .foregroundStyle(.yellow)
                    .lineLimit(2)
            }
            if context.state.replies.isEmpty {
                IslandButtons()
            } else {
                ForEach(Array(context.state.replies.prefix(3).enumerated()), id: \.offset) { index, reply in
                    Button(intent: CopyReplyIntent(index: index)) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(reply.text).font(.caption.weight(.semibold))
                            Text(reply.meaning).font(.caption2).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                    .tint(.cyan)
                }
            }
        }
        .padding()
    }
}
