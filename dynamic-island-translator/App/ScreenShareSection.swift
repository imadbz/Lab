import ReplayKit
import SwiftUI

/// The zero-setup way in: Start → confirm the system sheet → in any chat, hold the island → Translate screen.
struct ScreenShareSection: View {
    @EnvironmentObject var model: LabModel
    @State private var picker = BroadcastPicker()

    var body: some View {
        Section {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                let sharing = ScreenShare.isSharing
                HStack {
                    Label(sharing ? "Reading your screen" : "Screen sharing is off",
                          systemImage: sharing ? "record.circle.fill" : "record.circle")
                        .foregroundStyle(sharing ? .red : .secondary)
                    Spacer()
                    Button(sharing ? "Stop" : "Start") {
                        Task {
                            if !sharing { await model.prepareScreenIsland() }
                            picker.open()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    // The system's own button has to be on screen; ours taps it.
                    .background {
                        picker
                            .frame(width: 1, height: 1)
                            .opacity(0.01)
                            .accessibilityHidden(true)
                    }
                }
            }
        } header: {
            Text("Read my screen")
        } footer: {
            Text("Tap Start and confirm. Then, in any chat app, hold the island and tap **Translate**. iOS shows a red indicator while your screen is shared; tap it or Stop to end.")
        }
    }
}

/// Wraps the system screen broadcast button, preset to this app's extension so the sheet has one choice.
struct BroadcastPicker: UIViewRepresentable {
    static let extensionID = "dev.lab.islandtranslator.broadcast"

    private let view: RPSystemBroadcastPickerView = {
        let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
        picker.preferredExtension = extensionID
        picker.showsMicrophoneButton = false
        return picker
    }()

    func makeUIView(context: Context) -> RPSystemBroadcastPickerView { view }
    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {}

    /// RPSystemBroadcastPickerView has no API to open it; tapping its inner button is the known way.
    func open() {
        for case let button as UIButton in view.subviews {
            button.sendActions(for: .touchUpInside)
        }
    }
}
