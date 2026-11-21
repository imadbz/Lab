import Foundation

enum Engine: String, CaseIterable, Identifiable {
    case apple = "Apple on-device"
    case mock = "Mock phrasebook"

    var id: String { rawValue }

    /// Apple's Translation framework may not work in the Simulator, so default to the mock there.
    static var preferred: Engine {
        #if targetEnvironment(simulator)
        return .mock
        #else
        return .apple
        #endif
    }
}

/// Tiny offline stand-in so the island can be explored in the Simulator.
enum MockTranslator {
    private static let phrasebook: [String: [String: String]] = [
        "es>en": [
            "hola": "Hello",
            "dónde estás": "Where are you?",
            "a qué hora llegas": "What time are you arriving?",
            "gracias": "Thank you",
            "te espero en la entrada": "I'll wait for you at the entrance",
            "tienes hambre": "Are you hungry?",
            "hasta luego": "See you later",
        ],
        "en>es": [
            "hello": "Hola",
            "where are you": "¿Dónde estás?",
            "thank you": "Gracias",
            "i'm on my way": "Voy en camino",
            "i'm running late": "Llego tarde",
            "see you soon": "¡Hasta pronto!",
        ],
        "ja>en": [
            "こんにちは": "Hello",
            "どこにいますか": "Where are you?",
            "ありがとう": "Thank you",
        ],
        "en>ja": [
            "hello": "こんにちは",
            "where are you": "どこにいますか？",
            "thank you": "ありがとう",
        ],
        "fr>en": [
            "bonjour": "Hello",
            "où es-tu": "Where are you?",
            "merci": "Thank you",
        ],
        "en>fr": [
            "hello": "Bonjour",
            "where are you": "Où es-tu ?",
            "thank you": "Merci",
        ],
    ]

    static func translate(_ text: String, from src: String, to tgt: String) -> String {
        let key = text
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        if let hit = phrasebook["\(src)>\(tgt)"]?[key] {
            return hit
        }
        return "[\(Lang.short(src))→\(Lang.short(tgt))] \(text)"
    }
}

/// A scripted chat (with pre-baked translations) to watch the island update while you're on the Home Screen.
struct DemoLine {
    let original: String
    let translated: String
    let incoming: Bool
    let pause: Double
}

enum Demo {
    static let chatName = "Sofía"
    static let theirs = "es"
    static let mine = "en"
    static let script: [DemoLine] = [
        .init(original: "¡Hola! ¿Ya llegaste a Madrid?",
              translated: "Hi! Have you arrived in Madrid yet?", incoming: true, pause: 5),
        .init(original: "Just landed! Taking the metro now.",
              translated: "¡Acabo de aterrizar! Voy a tomar el metro.", incoming: false, pause: 5),
        .init(original: "Perfecto. Te espero en la salida de Sol, al lado de la librería.",
              translated: "Perfect. I'll wait for you at the Sol exit, next to the bookstore.", incoming: true, pause: 5),
        .init(original: "Si tienes hambre, conozco un sitio de churros increíble 😋",
              translated: "If you're hungry, I know an amazing churros place 😋", incoming: true, pause: 5),
        .init(original: "Yes please! 15 minutes away.",
              translated: "¡Sí, por favor! Estoy a 15 minutos.", incoming: false, pause: 4),
        .init(original: "Genial, ¡hasta ahora!",
              translated: "Great, see you soon!", incoming: true, pause: 0),
    ]
}

struct FitSample: Identifiable {
    let id = UUID()
    let title: String
    let text: String
    let lang: String
}

enum FitSamples {
    static let all: [FitSample] = [
        .init(title: "Tiny", text: "OK 👍", lang: "en"),
        .init(title: "Short question", text: "Where are you?", lang: "en"),
        .init(title: "Typical chat line", text: "I'll wait for you at the Sol exit, next to the bookstore.", lang: "en"),
        .init(title: "Long message",
              text: "Sorry, I'm running about 20 minutes late because the train broke down — can we meet at the café next to the main entrance instead of the platform?",
              lang: "en"),
        .init(title: "Japanese (dense script)", text: "駅に何時に着きますか？少し遅れそうなので、改札の前で待っていてください。", lang: "ja"),
        .init(title: "Arabic (right-to-left)", text: "أين أنت؟ أنا أنتظرك عند المدخل الرئيسي بجانب المقهى.", lang: "ar"),
        .init(title: "German (long words)",
              text: "Die Straßenbahnhaltestelle ist direkt gegenüber der Bundesverwaltungsgerichtsbibliothek.", lang: "de"),
        .init(title: "Paragraph",
              text: "Hey! Quick update on tonight: the restaurant moved our booking to 8:30 because of a private event, so there's no rush. If you get here early, there's a nice rooftop bar two doors down where we could grab a drink first. Also, bring a jacket — it gets cold by the river after dark.",
              lang: "en"),
    ]

    static func filler(_ count: Int) -> String {
        let base = "The quick brown fox jumps over the lazy dog. "
        var text = ""
        while text.count < count { text += base }
        return String(text.prefix(count))
    }
}
