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
    /// Anthropic only: the workspace a key made outside any workspace runs in.
    /// Optional so an older server that doesn't send it still decodes.
    public var workspaceId: String?
    public var isActive: Bool
    public var maskedKey: String
    public let updatedAt: Date
}

/// Payload for saving a provider key. Encoded with `.convertToSnakeCase`, so
/// `apiKey`/`baseUrl` become `api_key`/`base_url` on the wire.
public struct NewAICredential: Encodable, Sendable {
    public var provider: AIProvider
    /// Empty keeps the key already saved for this provider (the server only
    /// requires one the first time), so a workspace can be added on its own.
    public var apiKey: String
    public var model: String
    public var baseUrl: String
    public var workspaceId: String

    public init(provider: AIProvider, apiKey: String, model: String = "", baseUrl: String = "",
                workspaceId: String = "") {
        self.provider = provider
        self.apiKey = apiKey
        self.model = model
        self.baseUrl = baseUrl
        self.workspaceId = workspaceId
    }

    enum CodingKeys: String, CodingKey {
        case provider, apiKey, model, baseUrl, workspaceId
    }

    /// The key is left out entirely when blank — the server refuses a blank
    /// key, but takes a missing one as "keep the saved key".
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(provider, forKey: .provider)
        if !apiKey.isEmpty { try container.encode(apiKey, forKey: .apiKey) }
        try container.encode(model, forKey: .model)
        try container.encode(baseUrl, forKey: .baseUrl)
        if provider == .anthropic { try container.encode(workspaceId, forKey: .workspaceId) }
    }
}
