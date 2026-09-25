import Foundation
import Security

public enum KeychainStore {
    private static let service = "com.nexorial.watchwhisper.pairing"
    public static func read(_ account: String) throws -> Data? {
        var query = base(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw StoreError.status(status) }
        return result as? Data
    }
    public static func save(_ data: Data, account: String) throws {
        let query = base(account)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let result = SecItemAdd(item as CFDictionary, nil)
            guard result == errSecSuccess else { throw StoreError.status(result) }
        } else if status != errSecSuccess { throw StoreError.status(status) }
    }
    public static func delete(_ account: String) throws {
        let status = SecItemDelete(base(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw StoreError.status(status) }
    }
    public static func random(count: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else { throw StoreError.status(status) }
        return Data(bytes)
    }
    private static func base(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: account]
    }
    public enum StoreError: Error { case status(OSStatus) }
}
