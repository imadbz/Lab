import Foundation
import Security
import UIKit

/// Minimal Claude Messages API client over URLSession (there's no official Swift SDK).
/// Uses structured outputs so the reply is guaranteed to match our JSON schema.
enum ClaudeClient {
    static let model = "claude-opus-5-5"
    /// "low" keeps latency down for a chat helper; raise to "medium"/"high" if reading quality suffers.
    static let effort = "low"
    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    // MARK: Screenshot → conversation, translation, tone note, suggested replies

    struct Reading: Decodable {
        struct Message: Decodable {
            let from: String
            let original: String
            let translation: String
        }

        struct Reply: Decodable {
            let text: String
            let meaning: String
        }

        let app: String
        let contact: String
        let theirLanguage: String
        let messages: [Message]
        let note: String
        let suggestedReplies: [Reply]
    }

    static func readScreenshot(_ image: UIImage, myLanguage: String, apiKey: String) async throws -> Reading {
        guard let jpeg = ScreenImages.jpeg(image) else { throw ScreenError.badImage }

        let system = """
        You read screenshots of chat conversations for someone who speaks \(languageName(myLanguage)) \
        and is talking with a person who writes in another language.

        - List the visible chat messages oldest first (at most the last 8). Bubbles from the other person \
        (usually left-aligned) are "them"; the user's own bubbles (usually right-aligned, colored) are "me". \
        Ignore timestamps, read receipts, reactions, the keyboard and other UI.
        - Translate every message into \(languageName(myLanguage)) naturally, keeping tone, emoji and the meaning \
        of slang. If a message is already in \(languageName(myLanguage)), repeat it as the translation.
        - their_language: BCP-47 code of the other person's language (e.g. "es", "ja", "zh-Hans").
        - contact: the other person's name from the chat header, or "" if not visible. app: the chat app, or "Unknown".
        - note: one short sentence about slang, tone or cultural nuance in their LATEST message that a literal \
        translation would miss; "" if there is nothing worth saying.
        - suggested_replies: 2 or 3 short, natural replies to their latest message, written in their language \
        ("text") with the meaning in \(languageName(myLanguage)) ("meaning").

        Everything is shown in the iPhone Dynamic Island, so keep translations faithful and replies short.
        """

        let content: [[String: Any]] = [
            ["type": "image",
             "source": ["type": "base64", "media_type": "image/jpeg", "data": jpeg.base64EncodedString()]],
            ["type": "text", "text": "Read this chat screenshot."],
        ]

        let data = try await send(system: system, content: content, schema: readingSchema, apiKey: apiKey)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Reading.self, from: data)
    }

    // MARK: Plain text translation (the "Claude AI" engine on the Translate tab)

    private struct Translation: Decodable {
        let translation: String
    }

    static func translate(_ text: String, from src: String, to tgt: String, apiKey: String) async throws -> String {
        let system = """
        Translate chat messages from \(languageName(src)) to \(languageName(tgt)). \
        Keep the tone, emoji and register of the original; sound like a native texter, not a textbook.
        """
        let schema: [String: Any] = [
            "type": "object",
            "additionalProperties": false,
            "required": ["translation"],
            "properties": ["translation": ["type": "string"]],
        ]
        let data = try await send(system: system, content: [["type": "text", "text": text]],
                                  schema: schema, apiKey: apiKey)
        return try JSONDecoder().decode(Translation.self, from: data).translation
    }

    // MARK: Transport

    private struct APIResponse: Decodable {
        struct Block: Decodable {
            let type: String
            let text: String?
        }

        let content: [Block]
        let stopReason: String?
    }

    private struct APIError: Decodable {
        struct Detail: Decodable {
            let type: String
            let message: String
        }

        let error: Detail
    }

    /// Sends one Messages API request and returns the JSON text of the structured output.
    private static func send(system: String, content: [[String: Any]], schema: [String: Any],
                             apiKey: String) async throws -> Data {
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 16000,
            "system": system,
            "messages": [["role": "user", "content": content]],
            "output_config": [
                "effort": effort,
                "format": ["type": "json_schema", "schema": schema],
            ],
            // If a safety classifier declines, the API re-runs the request on a fallback model in the same call.
            "fallbacks": "default",
        ]

        var request = URLRequest(url: endpoint, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            let message = (try? JSONDecoder().decode(APIError.self, from: data))?.error.message
                ?? String(data: data, encoding: .utf8) ?? "no body"
            throw ScreenError.api("Claude API \(status): \(message)")
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let parsed = try decoder.decode(APIResponse.self, from: data)
        switch parsed.stopReason {
        case "refusal": throw ScreenError.api("Claude declined to read this one.")
        case "max_tokens": throw ScreenError.api("Claude's answer was cut off — try a smaller screenshot.")
        default: break
        }
        let json = parsed.content.filter { $0.type == "text" }.compactMap(\.text).joined()
        guard !json.isEmpty else { throw ScreenError.api("Claude returned no text.") }
        return Data(json.utf8)
    }

    private static var readingSchema: [String: Any] {
        let string: [String: Any] = ["type": "string"]
        let message: [String: Any] = [
            "type": "object",
            "additionalProperties": false,
            "required": ["from", "original", "translation"],
            "properties": [
                "from": ["type": "string", "enum": ["them", "me"]],
                "original": string,
                "translation": string,
            ],
        ]
        let reply: [String: Any] = [
            "type": "object",
            "additionalProperties": false,
            "required": ["text", "meaning"],
            "properties": ["text": string, "meaning": string],
        ]
        return [
            "type": "object",
            "additionalProperties": false,
            "required": ["app", "contact", "their_language", "messages", "note", "suggested_replies"],
            "properties": [
                "app": string,
                "contact": string,
                "their_language": string,
                "messages": ["type": "array", "items": message],
                "note": string,
                "suggested_replies": ["type": "array", "items": reply],
            ],
        ]
    }

    private static func languageName(_ code: String) -> String {
        Locale(identifier: "en").localizedString(forIdentifier: code) ?? code
    }
}

/// Stores the API key in the Keychain (readable after first unlock, so background Shortcuts can use it).
enum Keychain {
    private static let base: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "dev.lab.islandtranslator",
        kSecAttrAccount as String: "anthropic-api-key",
    ]

    static var apiKey: String? {
        get {
            var query = base
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var item: CFTypeRef?
            guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
                  let data = item as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        }
        set {
            SecItemDelete(base as CFDictionary)
            guard let newValue, !newValue.isEmpty else { return }
            var add = base
            add[kSecValueData as String] = Data(newValue.utf8)
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(add as CFDictionary, nil)
        }
    }
}
