import Foundation
import Security

enum CredentialKey: String, CaseIterable {
    case aiAPIKey = "ai-api-key"
    case longbridgeAppKey = "longbridge-app-key"
    case longbridgeAppSecret = "longbridge-app-secret"
    case longbridgeAccessToken = "longbridge-access-token"
}

enum CredentialStoreError: LocalizedError {
    case keychain(OSStatus)

    var errorDescription: String? {
        localizedDescription(locale: .current)
    }

    func localizedDescription(locale: Locale) -> String {
        switch self {
        case let .keychain(status):
            String(
                format: String(localized: "error.keychain_format", locale: locale),
                status
            )
        }
    }
}

enum CredentialStore {
    private static let service = "com.tradelab.backtest.v2.credentials"

    static func value(for key: CredentialKey) -> String? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func hasValue(for key: CredentialKey) -> Bool {
        guard let value = value(for: key) else { return false }
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func set(_ value: String, for key: CredentialKey) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            try remove(key)
            return
        }
        let data = Data(trimmed.utf8)
        let query = baseQuery(for: key)
        let attributes = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw CredentialStoreError.keychain(addStatus) }
        } else if status != errSecSuccess {
            throw CredentialStoreError.keychain(status)
        }
    }

    static func remove(_ key: CredentialKey) throws {
        let status = SecItemDelete(baseQuery(for: key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialStoreError.keychain(status)
        }
    }

    private static func baseQuery(for key: CredentialKey) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]
    }
}
