import Foundation

public enum STTSClientError: Error, Sendable, Equatable {
    case invalidResponse(String)
    case requestFailed(status: Int, code: String?)
    case transport(String)
    case credentialUnavailable

    /// The Worker answers `400 INVALID_REQUEST` for a conversation handle that
    /// failed to open (e.g. after rotation or expiry). Mirrors the web
    /// client's single recreate-and-retry.
    public var isStaleConversation: Bool {
        if case .requestFailed(400, "INVALID_REQUEST") = self { return true }
        return false
    }
}
