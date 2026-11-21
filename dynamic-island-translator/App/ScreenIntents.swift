import AppIntents
import UniformTypeIdentifiers
import UIKit

/// Shortcuts action: "Take Screenshot" → "Translate Screenshot".
/// Put that two-step shortcut on the Action button or Back Tap, press it inside WhatsApp,
/// and the latest incoming message (plus suggested replies, with the Claude reader) lands in the island
/// without leaving the chat. Conforming to LiveActivityIntent lets it start/update the island from the background.
struct TranslateScreenshotIntent: AppIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Translate Screenshot"
    static let description = IntentDescription(
        "Reads a chat screenshot, translates the latest message and shows it in the Dynamic Island."
    )

    @Parameter(title: "Screenshot", supportedContentTypes: [.image])
    var screenshot: IntentFile

    @Parameter(title: "Reader", default: .claude)
    var reader: ReaderMode

    static var parameterSummary: some ParameterSummary {
        Summary("Translate \(\.$screenshot) with \(\.$reader)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        guard let image = UIImage(data: screenshot.data) else { throw ScreenError.badImage }
        let result = try await LabModel.shared.readScreen(image, mode: reader)
        let text = result.latestTranslation
        return .result(value: text, dialog: "\(text)")
    }
}
