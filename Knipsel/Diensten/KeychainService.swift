import Foundation
import OSLog
import Security

/// Geheimen (de Claude-sleutel) in de Keychain, nooit in UserDefaults. Patroon uit FableFlux.
/// Alleen op dit toestel (`ThisDeviceOnly`): de sleutel gaat niet mee via iCloud-sleutelhanger.
enum KeychainService {
    private static let service = "com.peterbijkerk.knipsel"
    private static let logger = Logger(subsystem: "com.peterbijkerk.knipsel", category: "Keychain")

    /// Eerst bijwerken, en alleen als er nog niets staat toevoegen: mislukt het schrijven, dan
    /// blijft de oude waarde staan.
    @discardableResult
    static func save(_ waarde: String, forKey sleutel: String) -> Bool {
        guard let data = waarde.data(using: .utf8) else { return false }
        let query = basisQuery(sleutel)
        var status = SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)
        if status == errSecItemNotFound {
            var attributen = query
            attributen[kSecValueData] = data
            attributen[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(attributen as CFDictionary, nil)
        }
        if status != errSecSuccess {
            logger.error("Keychain bewaren mislukt voor '\(sleutel, privacy: .public)': OSStatus \(status)")
        }
        return status == errSecSuccess
    }

    static func load(forKey sleutel: String) -> String? {
        var query = basisQuery(sleutel)
        query[kSecReturnData] = kCFBooleanTrue
        query[kSecMatchLimit] = kSecMatchLimitOne
        var resultaat: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &resultaat)
        guard status == errSecSuccess, let data = resultaat as? Data else {
            if status != errSecItemNotFound {
                logger.error("Keychain lezen mislukt voor '\(sleutel, privacy: .public)': OSStatus \(status)")
            }
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func delete(forKey sleutel: String) -> Bool {
        let status = SecItemDelete(basisQuery(sleutel) as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            logger.error("Keychain verwijderen mislukt voor '\(sleutel, privacy: .public)': OSStatus \(status)")
        }
        return status == errSecSuccess || status == errSecItemNotFound
    }

    private static func basisQuery(_ sleutel: String) -> [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: sleutel]
    }
}
