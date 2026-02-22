// meta: created=2026-02-21 updated=2026-02-22 checked=never
import Foundation
import Security
import os

/// Shares UsageSnapshot between the main app and widget extension via Keychain.
/// Both apps must be sandboxed and signed by the same team.
public enum SnapshotStore {

    private static let log = Logger(subsystem: "grad13.weathercc", category: "SnapshotStore")
    private static let keychainService = "grad13.weathercc.snapshot"
    private static let keychainAccount = "usageSnapshot"

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    public static func save(_ snapshot: UsageSnapshot) {
        do {
            let data = try encoder.encode(snapshot)

            // Try update first (faster than delete+add)
            let searchQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: keychainService,
                kSecAttrAccount as String: keychainAccount,
            ]
            let updateAttrs: [String: Any] = [
                kSecValueData as String: data,
            ]
            var status = SecItemUpdate(searchQuery as CFDictionary, updateAttrs as CFDictionary)

            if status == errSecItemNotFound {
                let addQuery: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: keychainService,
                    kSecAttrAccount as String: keychainAccount,
                    kSecValueData as String: data,
                ]
                status = SecItemAdd(addQuery as CFDictionary, nil)
            }

            if status == errSecSuccess {
                log.info("save: \(data.count) bytes")
            } else {
                log.error("save: failed, status=\(status)")
            }
        } catch {
            log.error("save: encode failed: \(error.localizedDescription)")
        }
    }

    public static func load() -> UsageSnapshot? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            log.error("load: status=\(status)")
            return nil
        }

        do {
            return try decoder.decode(UsageSnapshot.self, from: data)
        } catch {
            log.error("load: decode failed: \(error.localizedDescription)")
            return nil
        }
    }
}
