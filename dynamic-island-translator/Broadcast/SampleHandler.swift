import CoreGraphics
import ImageIO
import ReplayKit
import UniformTypeIdentifiers
import VideoToolbox

/// Screen broadcast extension: runs while "Start" in the app has screen sharing on.
///
/// It can see the whole screen but can't touch the Live Activity (iOS refuses ActivityKit here),
/// so all it does is keep a recent frame in the App Group folder for the app to read.
/// Extensions like this one are killed past about 50 MB, so frames are scaled down and kept as JPEG.
final class SampleHandler: RPBroadcastSampleHandler {
    /// Seconds between kept frames.
    private let interval: TimeInterval = 0.5
    /// The long edge of a kept frame, in pixels. Enough for Vision OCR and for Claude (which wants ≤ 1568).
    private let maxEdge: CGFloat = 1568
    /// Frames waiting to be written. The one written is about a second old, so the expanded island
    /// you just opened to tap "Translate screen" isn't covering the chat in it.
    private var recent: [Data] = []
    private let keep = 3
    private var lastKept = Date.distantPast

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        ScreenShare.clear()
    }

    override func broadcastFinished() {
        recent.removeAll()
        ScreenShare.clear()
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video else { return }
        let now = Date()
        guard now.timeIntervalSince(lastKept) >= interval,
              let pixels = CMSampleBufferGetImageBuffer(sampleBuffer),
              let jpeg = jpeg(from: pixels)
        else { return }
        lastKept = now

        recent.append(jpeg)
        if recent.count > keep { recent.removeFirst(recent.count - keep) }
        // Before the buffer fills (sharing just started), the newest frame is the best there is.
        ScreenShare.writeFrame(recent.count == keep ? recent[0] : jpeg)
    }

    private func jpeg(from pixels: CVPixelBuffer) -> Data? {
        var full: CGImage?
        VTCreateCGImageFromCVPixelBuffer(pixels, options: nil, imageOut: &full)
        guard let full else { return nil }

        let scale = min(1, maxEdge / CGFloat(max(full.width, full.height)))
        let width = Int((CGFloat(full.width) * scale).rounded())
        let height = Int((CGFloat(full.height) * scale).rounded())
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(full, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let small = context.makeImage() else { return nil }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, small, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
