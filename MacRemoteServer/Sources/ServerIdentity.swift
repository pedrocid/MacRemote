import Foundation

struct ServerIdentity {
    static let defaultsKey = "MacRemoteServer.serverId"

    let id: String

    init(defaults: UserDefaults = .standard) {
        if let storedID = defaults.string(forKey: Self.defaultsKey),
           UUID(uuidString: storedID) != nil {
            id = storedID
        } else {
            let newID = UUID().uuidString
            defaults.set(newID, forKey: Self.defaultsKey)
            id = newID
        }
    }
}
