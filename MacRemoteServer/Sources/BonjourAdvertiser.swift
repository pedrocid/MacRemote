import Foundation
import Network

/// Advertises the server on the local network using Bonjour/mDNS
final class BonjourAdvertiser: NSObject {

    private var netService: NetService?
    private var listener: NWListener?

    private(set) var isAdvertising = false

    func startAdvertising(port: UInt16) {
        stopAdvertising()

        netService = NetService(
            domain: NetworkConstants.serviceDomain,
            type: NetworkConstants.serviceType,
            name: Host.current().localizedName ?? NetworkConstants.serviceName,
            port: Int32(port)
        )

        netService?.delegate = self
        netService?.publish()

        print("[Bonjour] Advertising service on port \(port)")
    }

    func stopAdvertising() {
        netService?.stop()
        netService = nil
        isAdvertising = false
    }
}

extension BonjourAdvertiser: NetServiceDelegate {
    func netServiceDidPublish(_ sender: NetService) {
        isAdvertising = true
        print("[Bonjour] Service published: \(sender.name)")
    }

    func netService(_ sender: NetService, didNotPublish errorDict: [String : NSNumber]) {
        isAdvertising = false
        print("[Bonjour] Failed to publish: \(errorDict)")
    }

    func netServiceDidStop(_ sender: NetService) {
        isAdvertising = false
        print("[Bonjour] Service stopped")
    }
}
