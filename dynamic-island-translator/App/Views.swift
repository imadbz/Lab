import SwiftUI
import UIKit

// MARK: - Translate tab

struct TranslateView: View {
    @EnvironmentObject var model: LabModel
    @FocusState private var inputFocused: Bool

    private var inputIsEmpty: Bool {
        model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Conversation") {
                    TextField("Chat name", text: $model.chatName)
                    LanguagePicker(title: "They speak", selection: $model.theirLang)
                    LanguagePicker(title: "I speak", selection: $model.myLang)
                }

                Section {
                    Picker("Direction", selection: $model.incoming) {
                        Text("They said…").tag(true)
                        Text("I want to say…").tag(false)
                    }
                    .pickerStyle(.segmented)

                    TextField(model.incoming ? "Paste their message" : "Type your reply",
                              text: $model.input, axis: .vertical)
                        .lineLimit(3...8)
                        .focused($inputFocused)

                    HStack {
                        PasteButton(payloadType: String.self) { strings in
                            Task { @MainActor in model.input = strings.first ?? "" }
                        }
                        .labelStyle(.iconOnly)
                        Spacer()
                        Button {
                            inputFocused = false
                            model.translateInput()
                        } label: {
                            Label("Translate → Island", systemImage: "sparkles")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(inputIsEmpty)
                    }
                } header: {
                    Text("Message")
                } footer: {
                    Text("Your own app's island only shows when the app is NOT on screen — swipe up to Home after translating. Long-press the island to expand it.")
                }

                if !model.history.isEmpty {
                    Section("Recent") {
                        ForEach(Array(model.history.prefix(6))) { message in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(message.translated)
                                Text("\(Lang.flag(message.src))→\(Lang.flag(message.tgt))  \(message.original)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .contextMenu {
                                Button("Copy translation") { UIPasteboard.general.string = message.translated }
                            }
                        }
                    }
                }

                Section {
                    Picker("Engine", selection: $model.engine) {
                        ForEach(Engine.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Toggle("Pop island open on incoming", isOn: $model.popWithAlert)
                    Button {
                        model.runDemo()
                    } label: {
                        Label("Run demo conversation", systemImage: "play.circle")
                    }
                    Button(role: .destructive) {
                        model.endIsland()
                    } label: {
                        Label("End Live Activity", systemImage: "stop.circle")
                    }
                    .disabled(!model.islandActive)
                } header: {
                    Text("Island")
                } footer: {
                    Text("“Pop open” sends an alert update, which briefly shows the expanded island without a long-press. The demo plays a 6-message chat over ~30 s.")
                }
            }
            .navigationTitle("Island Translator")
            .onChange(of: model.focusInput) {
                if model.focusInput {
                    inputFocused = true
                    model.focusInput = false
                }
            }
        }
    }
}

struct LanguagePicker: View {
    let title: String
    @Binding var selection: String

    var body: some View {
        Picker(title, selection: $selection) {
            ForEach(Lang.all) { lang in
                Text("\(Lang.flag(lang.code)) \(lang.name)").tag(lang.code)
            }
        }
    }
}

// MARK: - Fit Lab tab

struct FitLabView: View {
    @EnvironmentObject var model: LabModel
    @State private var length: Double = 80

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(FitSamples.all) { sample in
                        Button {
                            model.pushFitTest(sample.text, lang: sample.lang)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(sample.title).font(.subheadline.weight(.semibold))
                                Text(sample.text).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                Text("\(sample.text.count) characters").font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                } header: {
                    Text("Samples")
                } footer: {
                    Text("Push one, swipe home, then long-press the island. Note where text truncates or shrinks.")
                }

                Section("Custom length") {
                    Slider(value: $length, in: 1...400, step: 1)
                    Text(FitSamples.filler(Int(length)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                    Button("Push \(Int(length)) characters") {
                        model.pushFitTest(FitSamples.filler(Int(length)), lang: "en")
                    }
                }

                Section {
                    Picker("Compact style", selection: $model.lab.compactStyle) {
                        ForEach(LabOptions.CompactStyle.allCases) { Text($0.rawValue.capitalized).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Stepper("Max lines: \(model.lab.lineLimit)", value: $model.lab.lineLimit, in: 1...8)
                    Toggle("Show original text", isOn: $model.lab.showOriginal)
                    Toggle("Shrink text to fit", isOn: $model.lab.shrinkToFit)
                } header: {
                    Text("Layout")
                } footer: {
                    Text("Changes re-render the running island instantly. “Snippet” puts the translation itself in the compact island to see how many characters survive.")
                }

                Section("Payload") {
                    LabeledContent("Content state", value: "\(model.lastStateBytes) / 4096 bytes")
                    ProgressView(value: min(Double(model.lastStateBytes) / 4096, 1))
                }
            }
            .navigationTitle("Fit Lab")
            .onChange(of: model.lab) { model.relayout() }
        }
    }
}

// MARK: - Log tab

struct LogView: View {
    @EnvironmentObject var model: LabModel

    var body: some View {
        NavigationStack {
            List(model.logLines) { line in
                Text(line.text).font(.caption.monospaced())
            }
            .overlay {
                if model.logLines.isEmpty {
                    ContentUnavailableView("No events yet", systemImage: "list.bullet.rectangle")
                }
            }
            .navigationTitle("Log")
            .toolbar {
                Button("Clear") { model.clearLog() }
            }
        }
    }
}
