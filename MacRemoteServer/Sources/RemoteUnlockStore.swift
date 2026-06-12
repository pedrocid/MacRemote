import Foundation
import Security

final class RemoteUnlockStore {
    private enum Account {
        static let password = "mac-password"
        static let token = "pairing-token"
    }

    private let service = "com.pedrocid.MacRemoteServer.remote-unlock"

    var password: String? {
        guard let data = read(account: Account.password) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    var token: Data? {
        read(account: Account.token)
    }

    var isConfigured: Bool {
        password?.isEmpty == false && token != nil
    }

    @discardableResult
    func configure(password: String) -> Bool {
        let trimmedPassword = password.trimmingCharacters(in: .newlines)
        guard !trimmedPassword.isEmpty else { return false }

        let passwordSaved = save(Data(trimmedPassword.utf8), account: Account.password)
        let tokenSaved = token != nil || save(Self.randomBytes(count: 32), account: Account.token)
        return passwordSaved && tokenSaved
    }

    func removeConfiguration() {
        delete(account: Account.password)
        delete(account: Account.token)
    }

    var formattedPairingKey: String? {
        token?.map { String(format: "%02X", $0) }
            .joined()
            .split(every: 8)
            .joined(separator: "-")
    }

    static func randomBytes(count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            return Data(UUID().uuidString.utf8)
        }
        return Data(bytes)
    }

    private func save(_ data: Data, account: String) -> Bool {
        delete(account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    private func read(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else {
            return nil
        }
        return result as? Data
    }

    private func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

private extension Collection {
    func split(every size: Int) -> [SubSequence] {
        guard size > 0 else { return [self[startIndex..<endIndex]] }
        return stride(from: 0, to: count, by: size).map { offset in
            let start = index(startIndex, offsetBy: offset)
            let end = index(start, offsetBy: Swift.min(size, count - offset))
            return self[start..<end]
        }
    }
}
