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
    /// Where generated files are saved; blank means the app's own
    /// "WORKS(c)OUT Applications" folder.
    public var folderName: String
    /// The server is set up for Google's file picker, so files and a folder
    /// can be chosen from Drive.
    public var pickerAvailable: Bool

    public init(connected: Bool = false, enabled: Bool = false,
                accountEmail: String = "", folderId: String = "",
                folderName: String = "", pickerAvailable: Bool = false) {
        self.connected = connected
        self.enabled = enabled
        self.accountEmail = accountEmail
        self.folderId = folderId
        self.folderName = folderName
        self.pickerAvailable = pickerAvailable
    }

    /// Lenient decode so a missing field defaults off rather than failing.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        connected = try container.decodeIfPresent(Bool.self, forKey: .connected) ?? false
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        accountEmail = try container.decodeIfPresent(String.self, forKey: .accountEmail) ?? ""
        folderId = try container.decodeIfPresent(String.self, forKey: .folderId) ?? ""
        folderName = try container.decodeIfPresent(String.self, forKey: .folderName) ?? ""
        pickerAvailable = try container.decodeIfPresent(Bool.self, forKey: .pickerAvailable) ?? false
    }
}
