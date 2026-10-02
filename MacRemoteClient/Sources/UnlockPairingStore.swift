import Foundation

struct UnlockTarget: Codable, Equatable, Sendable {
    let serverId: String
    let displayName: String
    let pairedAt: Date
}

protocol UnlockTokenStoring: AnyObject {
    func readToken() throws -> Data?
    func saveToken(_ data: Data) throws
    func deleteToken() throws
}

enum PairingState: Equatable, Sendable {
    case unpaired
    case paired(UnlockTarget)
    case tokenOnlyLegacy
}

struct PairingSnapshot: Equatable, Sendable {
    let token: Data
    let target: UnlockTarget?
}

final class UnlockPairingStore: @unchecked Sendable {
    static let targetKey = "MacRemote.unlockTarget"

    private let tokens: UnlockTokenStoring
    private let defaults: UserDefaults
    private let lock = NSLock()

    init(tokens: UnlockTokenStoring, defaults: UserDefaults = .standard) {
        self.tokens = tokens
        self.defaults = defaults
    }

    func snapshot() throws -> PairingSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        guard let token = try tokens.readToken() else { return nil }
        return PairingSnapshot(token: token, target: readTarget())
    }

    func state() -> PairingState {
        lock.lock()
        defer { lock.unlock() }
        let boundTarget = readTarget()
        do {
            guard try tokens.readToken() != nil else { return .unpaired }
            return boundTarget.map(PairingState.paired) ?? .tokenOnlyLegacy
        } catch {
            // A read failure leaves token presence unknown; report only the known binding.
            return boundTarget.map(PairingState.paired) ?? .unpaired
        }
    }

    func target() -> UnlockTarget? {
        lock.lock()
        defer { lock.unlock() }
        return readTarget()
    }

    func pair(token: Data, serverId: String?, displayName: String, now: Date = Date()) throws {
        lock.lock()
        defer { lock.unlock() }
        try tokens.saveToken(token)
        if let serverId {
            let target = UnlockTarget(serverId: serverId, displayName: displayName, pairedAt: now)
            defaults.set(try JSONEncoder().encode(target), forKey: Self.targetKey)
        } else {
            defaults.removeObject(forKey: Self.targetKey)
        }
    }

    func unpair() throws {
        lock.lock()
        defer { lock.unlock() }
        defaults.removeObject(forKey: Self.targetKey)
        try tokens.deleteToken()
    }

    private func readTarget() -> UnlockTarget? {
        guard let data = defaults.data(forKey: Self.targetKey) else {
            if defaults.object(forKey: Self.targetKey) != nil {
                defaults.removeObject(forKey: Self.targetKey)
            }
            return nil
        }
        guard let target = try? JSONDecoder().decode(UnlockTarget.self, from: data) else {
            defaults.removeObject(forKey: Self.targetKey)
            return nil
        }
        return target
    }
}
