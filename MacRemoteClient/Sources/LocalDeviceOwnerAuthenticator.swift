import Foundation
import LocalAuthentication

final class LocalDeviceOwnerAuthenticator: DeviceOwnerAuthenticating, @unchecked Sendable {
    private let lock = NSLock()
    private var current: LAContext?
    private var cancellationPending = false

    func authenticate(reason: String) async throws {
        let context = LAContext()
        context.localizedCancelTitle = String(localized: "cancel")
        context.touchIDAuthenticationAllowableReuseDuration = 0

        let installed = lock.withLock { () -> Bool in
            if cancellationPending {
                cancellationPending = false
                return false
            }
            current = context
            return true
        }
        guard installed else { throw AuthenticationError.cancelled }

        defer {
            lock.withLock {
                current = nil
                cancellationPending = false
            }
        }

        do {
            guard try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) else {
                throw AuthenticationError.failed
            }
        } catch let error as LAError {
            switch error.code {
            case .userCancel, .systemCancel, .appCancel:
                throw AuthenticationError.cancelled
            case .notInteractive:
                throw AuthenticationError.notInteractive
            default:
                throw AuthenticationError.failed
            }
        } catch {
            throw AuthenticationError.failed
        }
    }

    func cancel() {
        let context = lock.withLock { () -> LAContext? in
            cancellationPending = true
            return current
        }
        context?.invalidate()
    }
}
