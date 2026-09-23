import Foundation

/// Cloudflare Access service token bound to the deployed Worker's Access
/// application. The secret never leaves the credential store.
public struct Credential: Codable, Sendable, Equatable {
    public var clientID: String
    public var clientSecret: String

    public init(clientID: String, clientSecret: String) {
        self.clientID = clientID
        self.clientSecret = clientSecret
    }

    private enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
        case clientSecret = "client_secret"
    }
}

/// Supplies authentication headers for every Worker request. When no
/// credential is configured the headers are empty, which supports local
/// development against `AUTH_MODE=local` Workers.
public protocol CredentialProviding: Sendable {
    func currentCredential() async throws -> Credential?
    func authHeaders() async throws -> [String: String]
}

public extension CredentialProviding {
    /// Cloudflare Access service-token headers. Access validates them at the
    /// edge and injects the `cf-access-jwt-assertion` header the Worker verifies.
    func authHeaders() async throws -> [String: String] {
        guard let credential = try await currentCredential() else { return [:] }
        return [
            "CF-Access-Client-Id": credential.clientID,
            "CF-Access-Client-Secret": credential.clientSecret
        ]
    }
}

/// Fixed in-memory provider for previews and tests.
public struct StaticCredentialProvider: CredentialProviding {
    private let credential: Credential?

    public init(credential: Credential?) {
        self.credential = credential
    }

    public func currentCredential() async throws -> Credential? {
        credential
    }
}
