import Foundation

extension RemoteUnlockService {
    static let livePairingStore = UnlockPairingStore(tokens: UnlockCredentialStore())

    static func configureLive() async {
        let locator = UnlockMacLocator(browser: NetworkUnlockBrowser()) { candidate in
            NetworkUnlockSession(endpoint: candidate.endpoint, name: candidate.name)
        }
        await shared.configure(
            pairing: livePairingStore,
            locator: locator,
            authenticator: LocalDeviceOwnerAuthenticator()
        )
    }
}
