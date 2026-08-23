import Foundation
import Security

/// Minimal Keychain wrapper for one purpose: persisting the Supabase auth session (an access
/// token + refresh token) across launches. Not `UserDefaults` — these are credentials, not
/// preferences, and the Keychain is the correct place for them on iOS.
///
/// Scoped to this app's own Keychain access group by default (no explicit group set), which
/// is normally stable across reinstalls of the *same* signed app — but plan §8 flags that
/// sideloading rewrites the bundle ID with a random suffix on each install, and whether that
/// suffix (and therefore this Keychain scope) survives a reinstall is one of §8's own open
/// items. Until that's confirmed, treat "signed back in after a reinstall" as expected, not a
/// bug, if it happens.
enum KeychainStore {
    private static let service = "com.tap2know.receiptscanner.bills.auth"

    static func save(_ data: Data, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func load(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
