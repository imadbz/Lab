import AppIntents
import Photos
import UIKit
import Vision

// iOS won't let an app read another app's chat, so the input is a SCREENSHOT of it.
// Two readers, same output:
//   • on-device — Vision OCR + bubble-side heuristics, then a translation engine. Free, private, offline.
//   • Claude    — one API call reads the whole chat, translates it, explains tone and suggests replies.

enum ReaderMode: String, AppEnum, CaseIterable, Identifiable {
    case onDevice
    case claude

    var id: String { rawValue }

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Screenshot reader"
    static let caseDisplayRepresentations: [ReaderMode: DisplayRepresentation] = [
        .onDevice: "On-device OCR",
        .claude: "Claude AI",
    ]

    var label: String {
        switch self {
        case .onDevice: return "On-device OCR"
        case .claude: return "Claude AI"
        }
    }
}

enum Speaker: String {
    case them, me, unknown
}

struct ScreenMessage: Identifiable {
    let id = UUID()
    let speaker: Speaker
    let text: String
    var translation: String?
}

struct ScreenResult {
    let mode: ReaderMode
    let messages: [ScreenMessage]
    let latestOriginal: String
    let latestTranslation: String
    let theirLang: String
    let contact: String?
    let note: String
    let replies: [SuggestedReply]
    let thumbnail: UIImage
    var elapsed: TimeInterval = 0
}

enum ScreenError: LocalizedError {
    case badImage, noText, noAPIKey, photosDenied, noScreenshot, notSharing
    case api(String)

    var errorDescription: String? {
        switch self {
        case .badImage: return "Couldn't read that image."
        case .noText: return "No chat messages found in the screenshot."
        case .noAPIKey: return "Add your Anthropic API key in the Screen tab to use the Claude reader."
        case .photosDenied: return "Allow Photos access to grab your latest screenshot."
        case .noScreenshot: return "No screenshots found in your library."
        case .notSharing: return "Screen sharing is off. Open Island Translator and tap Start."
        case .api(let message): return message
        }
    }
}

// MARK: - On-device OCR

enum ScreenOCR {
    struct Line {
        let text: String
        let box: CGRect // Vision coordinates: normalized, origin bottom-left
    }

    static func messages(in image: UIImage) async throws -> [ScreenMessage] {
        guard let cgImage = image.cgImage else { throw ScreenError.badImage }
        let lines = try await Task.detached(priority: .userInitiated) {
            try recognize(cgImage)
        }.value
        return group(lines)
    }

    private static func recognize(_ cgImage: CGImage) throws -> [Line] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
        return (request.results ?? []).compactMap { observation in
            observation.topCandidates(1).first.map { Line(text: $0.string, box: observation.boundingBox) }
        }
    }

    /// Turns raw OCR lines into chat messages:
    /// drops the status bar / header / input bar and timestamps,
    /// decides the side from left vs right margin, and merges lines of the same bubble.
    static func group(_ lines: [Line]) -> [ScreenMessage] {
        let timestamp = try! NSRegularExpression(pattern: #"^\d{1,2}[:.]\d{2}(\s?[AaPp]\.?[Mm]\.?)?\s*[✓✔︎]*$"#)
        let trailingTime = try! NSRegularExpression(pattern: #"\s+\d{1,2}:\d{2}(\s?[AaPp][Mm])?\s*[✓✔︎]*$"#)

        let usable = lines
            .filter { $0.box.midY < 0.90 && $0.box.midY > 0.08 } // header/status bar, input bar
            .filter { line in
                let range = NSRange(line.text.startIndex..., in: line.text)
                return timestamp.firstMatch(in: line.text, range: range) == nil
            }
            .sorted { $0.box.maxY > $1.box.maxY } // top → bottom = oldest → newest

        var messages: [ScreenMessage] = []
        var lastBox: CGRect?

        for line in usable {
            let leftGap = line.box.minX
            let rightGap = 1 - line.box.maxX
            let speaker: Speaker
            if leftGap + 0.06 < rightGap {
                speaker = .them
            } else if rightGap + 0.06 < leftGap {
                speaker = .me
            } else {
                speaker = .unknown // centered: dates, "Messages are end-to-end encrypted", etc.
            }

            var text = line.text
            let range = NSRange(text.startIndex..., in: text)
            text = trailingTime.stringByReplacingMatches(in: text, range: range, withTemplate: "")
            guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { continue }

            // Same bubble if same side and the vertical gap is under ~1 line height.
            if let previous = messages.last, let lastBox, previous.speaker == speaker,
               lastBox.minY - line.box.maxY < line.box.height * 1.1 {
                messages[messages.count - 1] = ScreenMessage(speaker: speaker, text: previous.text + " " + text)
            } else {
                messages.append(ScreenMessage(speaker: speaker, text: text))
            }
            lastBox = line.box
        }
        return messages
    }
}

// MARK: - Images

enum ScreenImages {
    /// The most recent screenshot in the photo library.
    static func latestScreenshot() async throws -> UIImage {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized || status == .limited else { throw ScreenError.photosDenied }

        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "(mediaSubtypes & %d) != 0",
                                        PHAssetMediaSubtype.photoScreenshot.rawValue)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = 1
        guard let asset = PHAsset.fetchAssets(with: .image, options: options).firstObject else {
            throw ScreenError.noScreenshot
        }

        let requestOptions = PHImageRequestOptions()
        requestOptions.deliveryMode = .highQualityFormat
        requestOptions.isNetworkAccessAllowed = true
        return try await withCheckedThrowingContinuation { continuation in
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: requestOptions) { data, _, _, _ in
                if let data, let image = UIImage(data: data) {
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(throwing: ScreenError.badImage)
                }
            }
        }
    }

    /// Downscale so the long edge is ≤ `maxEdge` px (Claude's sweet spot is ~1568) and JPEG-encode.
    static func jpeg(_ image: UIImage, maxEdge: CGFloat = 1568, quality: CGFloat = 0.8) -> Data? {
        let size = image.size
        let scale = min(1, maxEdge / max(size.width, size.height))
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: quality)
    }

    static func thumbnail(_ image: UIImage) -> UIImage {
        guard let data = jpeg(image, maxEdge: 400, quality: 0.7), let thumb = UIImage(data: data) else { return image }
        return thumb
    }
}
