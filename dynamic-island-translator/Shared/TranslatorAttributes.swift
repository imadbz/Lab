import ActivityKit
import Foundation

/// The data model of the Live Activity that drives the Dynamic Island.
/// Compiled into BOTH the app (which starts/updates it) and the widget extension (which draws it).
struct TranslatorAttributes: ActivityAttributes {
    /// Everything that can change while the activity is running.
    /// Apple caps this (encoded) at 4 KB — the Fit Lab tab shows how close you are.
    public struct ContentState: Codable, Hashable {
        var original: String
        var translated: String
        var sourceLang: String
        var targetLang: String
        var incoming: Bool
        var unread: Int
        var updatedAt: Date
        var lab: LabOptions
    }

    /// Fixed for the lifetime of the activity.
    var chatName: String
}

/// Layout knobs you can twiddle live from the Fit Lab tab.
struct LabOptions: Codable, Hashable {
    enum CompactStyle: String, Codable, CaseIterable, Identifiable {
        case flags    // 🇪🇸 … unread badge
        case codes    // ES›EN … unread badge
        case snippet  // 🇪🇸 … first words of the translation
        var id: String { rawValue }
    }

    var compactStyle: CompactStyle = .flags
    var lineLimit: Int = 3
    var showOriginal: Bool = true
    var shrinkToFit: Bool = true
}

struct LanguageOption: Identifiable, Hashable {
    let code: String
    let name: String
    var id: String { code }
}

enum Lang {
    static let all: [LanguageOption] = [
        .init(code: "en", name: "English"),
        .init(code: "es", name: "Spanish"),
        .init(code: "fr", name: "French"),
        .init(code: "de", name: "German"),
        .init(code: "it", name: "Italian"),
        .init(code: "pt", name: "Portuguese"),
        .init(code: "ja", name: "Japanese"),
        .init(code: "ko", name: "Korean"),
        .init(code: "zh-Hans", name: "Chinese"),
        .init(code: "ar", name: "Arabic"),
        .init(code: "ru", name: "Russian"),
        .init(code: "tr", name: "Turkish"),
        .init(code: "hi", name: "Hindi"),
    ]

    private static let flags: [String: String] = [
        "en": "🇬🇧", "es": "🇪🇸", "fr": "🇫🇷", "de": "🇩🇪", "it": "🇮🇹", "pt": "🇧🇷",
        "ja": "🇯🇵", "ko": "🇰🇷", "zh-Hans": "🇨🇳", "ar": "🇸🇦", "ru": "🇷🇺", "tr": "🇹🇷", "hi": "🇮🇳",
    ]

    static func flag(_ code: String) -> String { flags[code] ?? "🌐" }
    static func short(_ code: String) -> String { String(code.prefix(2)).uppercased() }
}
