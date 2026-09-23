import Foundation
import Security
import STTSCore

/// Keychain-backed credential store. The Cloudflare Access service token is
/// stored as a single generic-password item with
/// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`; it is never written to
/// UserDefaults, logged, or displayed back after saving.
struct KeychainCredentialStore: CredentialProviding {
    static let service = "com.stts.mobile.credentials"
    static let account = "cloudflare-access"

    func currentCredential() async throws -> Credential? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw STTSClientError.credentialUnavailable
        }
        guard let data = item as? Data else {
            throw STTSClientError.credentialUnavailable
        }
        return try JSONDecoder().decode(Credential.self, from: data)
    }

    func store(_ credential: Credential) throws {
        try clear()
        let data = try JSONEncoder().encode(credential)
        var add = baseQuery()
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw STTSClientError.credentialUnavailable
        }
    }

    func clear() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw STTSClientError.credentialUnavailable
        }
    }

    /// Existence check only — the secret is never read for display.
    func hasCredential() -> Bool {
        SecItemCopyMatching(baseQuery() as CFDictionary, nil) == errSecSuccess
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account
        ]
    }
}
