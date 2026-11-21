import Foundation

/// The hand-off between the screen broadcast extension and the app, through the shared App Group folder.
///
/// The extension sees every frame while screen sharing is on, but iOS won't let it touch the
/// Live Activity. So it keeps writing a recent frame to `frame.jpg`; when you tap "Translate screen"
/// in the island, the app (woken by that button) reads the frame and updates the island.
enum ScreenShare {
    /// Must match `com.apple.security.application-groups` in project.yml for the app and the extension.
    static let group = "group.dev.lab.islandtranslator"

    /// A frame older than this means sharing stopped (the extension writes one every half second).
    static let maxFrameAge: TimeInterval = 10

    static var folder: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
    }

    static var frameURL: URL? { folder?.appendingPathComponent("frame.jpg") }

    /// Called by the extension. Written atomically, so the app never reads half a file.
    static func writeFrame(_ jpeg: Data) {
        guard let url = frameURL else { return }
        try? jpeg.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    /// Called by the extension when sharing ends, so no picture of the screen stays behind.
    static func clear() {
        guard let url = frameURL else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// The most recent frame, if sharing is on.
    static func latestFrame() -> Data? {
        guard let url = frameURL,
              let written = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
              Date().timeIntervalSince(written) < maxFrameAge
        else { return nil }
        return try? Data(contentsOf: url)
    }

    static var isSharing: Bool {
        guard let url = frameURL,
              let written = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        else { return false }
        return Date().timeIntervalSince(written) < maxFrameAge
    }
}
