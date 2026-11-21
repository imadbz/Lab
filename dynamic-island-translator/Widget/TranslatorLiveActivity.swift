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
                // EXPANDED (long-press, or briefly on an alert update). About 370 x 160 pt in all:
                // a row beside the camera, a strip below it, and the bottom region. The actions live
                // beside the camera so the whole bottom region is the message.
                DynamicIslandExpandedRegion(.leading) {
                    Text("\(Lang.flag(context.state.sourceLang))→\(Lang.flag(context.state.targetLang))")
                        .font(.title3)
                        .padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    IslandActions(state: context.state)
                }
                DynamicIslandExpandedRegion(.center) {
                    // The strip under the camera: the AI's tone note when there is one, else who and when.
                    if context.state.note.isEmpty {
                        Text("\(context.attributes.chatName) · \(context.state.updatedAt, style: .time)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        Label(context.state.note, systemImage: "lightbulb")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ExpandedBottom(state: context.state)
                }
            } compactLeading: {
                // COMPACT, the resting state, either side of the camera.
                CompactLeading(state: context.state)
            } compactTrailing: {
                CompactTrailing(state: context.state)
            } minimal: {
                // MINIMAL, when another app's Live Activity is also running.
                Text(Lang.flag(context.state.sourceLang))
            }
            // A tap anywhere that isn't a button opens the reply composer.
            .widgetURL(URL(string: "islandtranslator://reply"))
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
        if state.busy {
            Image(systemName: "ellipsis")
                .foregroundStyle(.cyan)
        } else {
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
}

// MARK: - Expanded

/// Beside the camera: Copy, and the main action, Translate (reads whatever chat is on screen now).
struct IslandActions: View {
    let state: TranslatorAttributes.ContentState

    var body: some View {
        HStack(spacing: 6) {
            Button(intent: CopyTranslationIntent()) {
                Image(systemName: "doc.on.doc")
            }
            .tint(.white)
            Button(intent: TranslateScreenIntent()) {
                Image(systemName: "text.viewfinder")
            }
            .tint(.cyan)
            .disabled(state.busy)
        }
        .font(.callout.weight(.semibold))
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .padding(.trailing, 4)
    }
}

struct ExpandedBottom: View {
    let state: TranslatorAttributes.ContentState

    /// One small line above the message: the reading state or the original. (The AI note sits under the camera.)
    private var captionShown: Bool { state.busy || state.lab.showOriginal }

    /// The bottom region holds about three lines of body text; a caption or the reply chips take one each.
    private var messageLines: Int {
        max(1, state.lab.lineLimit - (captionShown ? 1 : 0) - (state.replies.isEmpty ? 0 : 1))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if state.busy {
                Label("Reading the screen…", systemImage: "text.viewfinder")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.cyan)
            } else if state.lab.showOriginal {
                Text(state.original)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            // Tap the message to swap it with the original.
            Button(intent: FlipIntent()) {
                Text(state.translated)
                    .font(.body.weight(.semibold))
                    .multilineTextAlignment(.leading)
                    .lineLimit(messageLines)
                    .minimumScaleFactor(state.lab.shrinkToFit ? 0.75 : 1)
                    // Wrap to messageLines instead of shrinking onto one line.
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .opacity(state.busy ? 0.5 : 1)
            }
            .buttonStyle(.plain)
            if !state.replies.isEmpty {
                ReplyChips(replies: state.replies)
            }
        }
        .padding(.horizontal, 4)
    }
}

/// Tap a chip: that reply (in their language) is on the clipboard, ready to paste into the chat.
struct ReplyChips: View {
    let replies: [SuggestedReply]

    var body: some View {
        HStack(spacing: 6) {
            // Two chips: three cut every reply to about ten characters.
            ForEach(Array(replies.prefix(2).enumerated()), id: \.offset) { index, reply in
                Button(intent: CopyReplyIntent(index: index)) {
                    Text(reply.text).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .font(.caption.weight(.semibold))
        .controlSize(.small)
        .buttonStyle(.bordered)
        .tint(.cyan)
    }
}

/// The Lock Screen's button row (the island keeps its actions beside the camera instead).
struct IslandButtons: View {
    var body: some View {
        HStack(spacing: 8) {
            // The main action: read whatever chat is on screen now (needs screen sharing on, see ScreenShare).
            Button(intent: TranslateScreenIntent()) {
                Label("Translate", systemImage: "text.viewfinder")
            }
            Group {
                Button(intent: CopyTranslationIntent()) {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                Button(intent: FlipIntent()) {
                    Label("Flip", systemImage: "arrow.left.arrow.right")
                }
                Link(destination: URL(string: "islandtranslator://reply")!) {
                    Label("Reply", systemImage: "arrowshape.turn.up.left")
                }
            }
            .labelStyle(.iconOnly)
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
