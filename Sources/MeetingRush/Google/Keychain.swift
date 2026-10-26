import Foundation
import Security

/// Stores one generic-password item per service and account in the login keychain.
enum Keychain {
    static func read(service: String, account: String) -> Data? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ] as CFDictionary, &result)
        return status == errSecSuccess ? result as? Data : nil
    }

    static func write(_ data: Data, service: String, account: String) {
        let query = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ] as CFDictionary
        if SecItemUpdate(query, [kSecValueData: data] as CFDictionary) == errSecItemNotFound {
            var item = query as! [CFString: Any]
            item[kSecValueData] = data
            SecItemAdd(item as CFDictionary, nil)
        }
    }
}
