import Foundation

/// The account's Google Drive connection status, as the server reports it. The
/// refresh token never leaves the server — only these fields cross the wire.
/// Decoded with the client's `.convertFromSnakeCase` (`account_email` →
/// `accountEmail`, `folder_id` → `folderId`).
public struct DriveConnection: Codable, Equatable, Sendable {
    /// A refresh token is stored (they've authorized their Drive).
    public var connected: Bool
    /// The Identity on/off toggle — uploads only happen when connected AND enabled.
    public var enabled: Bool
    public var accountEmail: String
    public var folderId: String

    public init(connected: Bool = false, enabled: Bool = false,
                accountEmail: String = "", folderId: String = "") {
        self.connected = connected
        self.enabled = enabled
        self.accountEmail = accountEmail
        self.folderId = folderId
    }

    /// Lenient decode so a missing field defaults off rather than failing.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        connected = try container.decodeIfPresent(Bool.self, forKey: .connected) ?? false
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        accountEmail = try container.decodeIfPresent(String.self, forKey: .accountEmail) ?? ""
        folderId = try container.decodeIfPresent(String.self, forKey: .folderId) ?? ""
    }
}
