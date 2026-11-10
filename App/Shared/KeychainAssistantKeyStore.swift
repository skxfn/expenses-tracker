import Foundation
import Security
import ExpenseCore

/// Ключ API ИИ-записи в Keychain: только на этом устройстве (`…ThisDeviceOnly`), не в UserDefaults,
/// не в резервной копии приложения и не в логах. Сервис — от bundle ID во время работы: SideStore может
/// дописать к нему `.<TeamID>`, поэтому ничего не хардкодим.
nonisolated struct KeychainAssistantKeyStore: AssistantKeyStore {
    enum KeychainError: Error {
        case status(OSStatus)
    }

    private let service = (Bundle.main.bundleIdentifier ?? "com.skxfn.expenses") + ".assistant"
    private let account = "apiKey"

    private var query: [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account]
    }

    func readKey() throws -> String? {
        var request = query
        request[kSecReturnData] = true
        request[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw KeychainError.status(status) }
        return String(data: data, encoding: .utf8)
    }

    func saveKey(_ key: String) throws {
        let data = Data(key.utf8)
        let update: [CFString: Any] = [kSecValueData: data, kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item.merge(update) { _, new in new }
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else { throw KeychainError.status(added) }
        } else if status != errSecSuccess {
            throw KeychainError.status(status)
        }
    }

    func deleteKey() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError.status(status) }
    }
}
