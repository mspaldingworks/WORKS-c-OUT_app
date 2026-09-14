import Foundation

/// An AI provider a user can bring their own API key for. Raw values match the
/// server's `LLMCredential.Provider` choices.
public enum AIProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case anthropic, openai, gemini, deepseek, custom

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .anthropic: return "Claude (Anthropic)"
        case .openai: return "OpenAI"
        case .gemini: return "Google Gemini"
        case .deepseek: return "DeepSeek"
        case .custom: return "Custom (OpenAI-compatible)"
        }
    }

    /// Where the user gets an API key (not a subscription) for this provider.
    public var keyURL: URL? {
        switch self {
        case .anthropic: return URL(string: "https://console.anthropic.com/settings/keys")
        case .openai: return URL(string: "https://platform.openai.com/api-keys")
        case .gemini: return URL(string: "https://aistudio.google.com/app/apikey")
        case .deepseek: return URL(string: "https://platform.deepseek.com/api_keys")
        case .custom: return nil
        }
    }

    /// Only the custom provider needs the user to supply a base URL.
    public var needsBaseURL: Bool { self == .custom }

    /// Shown as the model field's placeholder — the server's default when blank.
    public var modelPlaceholder: String {
        switch self {
        case .anthropic: return "claude-opus-5"
        case .openai: return "gpt-4o"
        case .gemini: return "gemini-2.5-flash"
        case .deepseek: return "deepseek-chat"
        case .custom: return "model name"
        }
    }

    /// Lenient: an unknown provider from the server decodes as `.custom` rather
    /// than failing the whole response.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = AIProvider(rawValue: raw) ?? .custom
    }
}

/// A saved provider key, as the server returns it — the key itself is never
/// sent back, only `maskedKey` (e.g. "…4a9f"). Decoded with the client's
/// `.convertFromSnakeCase`, so `base_url`/`masked_key`/`is_active` map here.
public struct AICredential: Codable, Identifiable, Equatable, Sendable {
    public let id: Int
    public var provider: AIProvider
    public var model: String
    public var baseUrl: String
    public var isActive: Bool
    public var maskedKey: String
    public let updatedAt: Date
}

/// Payload for saving a provider key. Encoded with `.convertToSnakeCase`, so
/// `apiKey`/`baseUrl` become `api_key`/`base_url` on the wire.
public struct NewAICredential: Encodable, Sendable {
    public var provider: AIProvider
    public var apiKey: String
    public var model: String
    public var baseUrl: String

    public init(provider: AIProvider, apiKey: String, model: String = "", baseUrl: String = "") {
        self.provider = provider
        self.apiKey = apiKey
        self.model = model
        self.baseUrl = baseUrl
    }
}
