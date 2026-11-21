import PhotosUI
import SwiftUI
import UIKit

/// Screenshot → island. Compare the on-device reader with the Claude reader on the same screenshot.
struct ScreenView: View {
    @EnvironmentObject var model: LabModel
    @State private var pickerItem: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            Form {
                ScreenShareSection()

                Section {
                    Picker("Reader", selection: $model.readerMode) {
                        ForEach(ReaderMode.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    PhotosPicker(selection: $pickerItem, matching: .screenshots) {
                        Label("Choose a screenshot", systemImage: "photo.on.rectangle")
                    }
                    Button {
                        model.processLatestScreenshot()
                    } label: {
                        Label("Use my latest screenshot", systemImage: "clock.arrow.circlepath")
                    }
                    if model.screenBusy {
                        HStack {
                            ProgressView()
                            Text("Reading…").foregroundStyle(.secondary)
                        }
                    }
                    if let error = model.screenError {
                        Text(error).foregroundStyle(.red).font(.callout)
                    }
                } header: {
                    Text("Read a chat screenshot")
                } footer: {
                    Text(model.readerMode == .claude
                         ? "Claude reads the whole chat, translates it, explains tone and suggests replies. The screenshot is sent to the Anthropic API."
                         : "Vision OCR runs on the phone; bubble side (them/me) is guessed from the margins. Nothing leaves the device unless the Translate engine is Claude.")
                }

                if let result = model.screenResult {
                    ResultSection(result: result)
                }

                Section {
                    SecureField("sk-ant-…", text: $model.apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    LabeledContent("Model", value: ClaudeClient.model)
                } header: {
                    Text("Claude API key")
                } footer: {
                    Text("Stored in the Keychain on this device. Get one at console.anthropic.com.")
                }

                Section("Use it without leaving the chat") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("1. Shortcuts app › **+** › add **Take Screenshot**")
                        Text("2. Add **Translate Screenshot** (Island Translator) and pick a reader")
                        Text("3. Settings › Action Button (or Accessibility › Touch › Back Tap) › that shortcut")
                        Text("4. In WhatsApp, press it → the translation lands in the island; replies are one tap away")
                    }
                    .font(.callout)
                }
            }
            .navigationTitle("Screen")
            .onChange(of: pickerItem) {
                guard let item = pickerItem else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        model.processScreen(image)
                    } else {
                        model.screenError = ScreenError.badImage.localizedDescription
                    }
                    pickerItem = nil
                }
            }
        }
    }
}

private struct ResultSection: View {
    let result: ScreenResult

    var body: some View {
        Section {
            HStack(alignment: .top, spacing: 12) {
                Image(uiImage: result.thumbnail)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 70)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 4) {
                    Text(result.latestTranslation).font(.headline)
                    Text(result.latestOriginal).font(.caption).foregroundStyle(.secondary)
                    Text("\(Lang.flag(result.theirLang)) \(result.contact ?? "—") · \(String(format: "%.1f", result.elapsed)) s · \(result.mode.label)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            if !result.note.isEmpty {
                Label(result.note, systemImage: "lightbulb").font(.callout)
            }
            ForEach(Array(result.replies.enumerated()), id: \.offset) { _, reply in
                Button {
                    UIPasteboard.general.string = reply.text
                } label: {
                    VStack(alignment: .leading) {
                        Text(reply.text)
                        Text(reply.meaning).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Latest from them")
        }

        Section("Everything it read (\(result.messages.count))") {
            ForEach(result.messages) { message in
                HStack(alignment: .top) {
                    Text(message.speaker == .me ? "ME" : message.speaker == .them ? "THEM" : "?")
                        .font(.caption2.weight(.bold).monospaced())
                        .foregroundStyle(message.speaker == .me ? Color.green : message.speaker == .them ? Color.cyan : Color.gray)
                        .frame(width: 40, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(message.text).font(.callout)
                        if let translation = message.translation {
                            Text(translation).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}
