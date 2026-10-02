import Foundation
import Security

enum UnlockCredentialError: Error, Equatable {
    case invalidKeyFormat
    case keychain(OSStatus)
}

final class UnlockCredentialStore: UnlockTokenStoring {
    private let service = "com.naduda.pr.MacRemoteClient.remote-unlock"
    private let account = "pairing-token"

    var token: Data? {
        try? readToken()
    }

    func readToken() throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecItemNotFound:
            return nil
        case errSecSuccess:
            guard let data = result as? Data else {
                throw UnlockCredentialError.keychain(errSecDecode)
            }
            return data
        default:
            throw UnlockCredentialError.keychain(status)
        }
    }

    var hasToken: Bool {
        token != nil
    }

    @discardableResult
    func save(pairingKey: String) -> Bool {
        do {
            try saveToken(Self.parsePairingKey(pairingKey))
            return true
        } catch {
            return false
        }
    }

    static func parsePairingKey(_ s: String) throws -> Data {
        let normalized = s
            .filter(\.isHexDigit)
            .uppercased()
        guard normalized.count == 64, let data = Data(hexString: normalized) else {
            throw UnlockCredentialError.invalidKeyFormat
        }
        return data
    }

    func saveToken(_ data: Data) throws {
        let match: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(match as CFDictionary, update as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else {
            throw UnlockCredentialError.keychain(status)
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: data
        ]
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw UnlockCredentialError.keychain(addStatus)
        }
    }

    func delete() {
        try? deleteToken()
    }

    func deleteToken() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw UnlockCredentialError.keychain(status)
        }
    }
}

private extension Data {
    init?(hexString: String) {
        guard hexString.count.isMultiple(of: 2) else { return nil }
        var data = Data()
        data.reserveCapacity(hexString.count / 2)
        var index = hexString.startIndex
        while index < hexString.endIndex {
            let next = hexString.index(index, offsetBy: 2)
            guard let byte = UInt8(hexString[index..<next], radix: 16) else {
                return nil
            }
            data.append(byte)
            index = next
        }
        self = data
    }
}
