import AppIntents

/// v1 always unlocks the Mac bound when the pairing key was saved (see design-decisions.md DEC-2); never a random Mac.
struct UnlockMacIntent: AppIntent {
    static let title: LocalizedStringResource = "intent_unlock_mac_title"
    static let description = IntentDescription("intent_unlock_mac_description")
    static var openAppWhenRun: Bool { false }
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresLocalDeviceAuthentication }

    @available(iOS 26.0, macOS 26.0, *)
    static var supportedModes: IntentModes { [.background, .foreground(.dynamic)] }

    func perform() async throws -> some IntentResult {
        await RemoteUnlockService.configureLive()
        let requireAuthentication = UnlockSettings.requireFaceIDForShortcut
        var outcome = await RemoteUnlockService.shared.unlock(
            route: .boundTarget,
            reason: String(localized: "unlock_auth_reason"),
            requireAuthentication: requireAuthentication
        )

        if outcome == .authenticationNeedsForeground, #available(iOS 26.0, macOS 26.0, *),
           systemContext.currentMode == .background,
           systemContext.currentMode.canContinueInForeground {
            do {
                try await continueInForeground(
                    IntentDialog(LocalizedStringResource(String.LocalizationValue(UnlockOutcome.authenticationNeedsForeground.localizationKey))),
                    alwaysConfirm: false
                )
                outcome = await RemoteUnlockService.shared.unlock(
                    route: .boundTarget,
                    reason: String(localized: "unlock_auth_reason"),
                    requireAuthentication: requireAuthentication
                )
            } catch {
                outcome = .authenticationNeedsForeground
            }
        }

        // Success is silent (no result dialog with a Done button); everything else is surfaced as an error.
        switch outcome {
        case .verified, .alreadyUnlocked:
            return .result()
        default:
            throw UnlockIntentError(message: LocalizedStringResource(String.LocalizationValue(outcome.localizationKey)))
        }
    }
}

enum UnlockSettings {
    static let requireFaceIDForShortcutKey = "unlock.requireFaceIDForShortcut"

    /// Default true. When the user turns it off, the Shortcut relies only on the intent's
    /// device-authentication policy (unlocked iPhone) and the app no longer opens for Face ID.
    static var requireFaceIDForShortcut: Bool {
        UserDefaults.standard.object(forKey: requireFaceIDForShortcutKey) as? Bool ?? true
    }
}

struct UnlockIntentError: Error, CustomLocalizedStringResourceConvertible {
    let message: LocalizedStringResource
    var localizedStringResource: LocalizedStringResource { message }
}

struct MacRemoteShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: UnlockMacIntent(),
            phrases: ["Unlock my Mac with \(.applicationName)", "\(.applicationName) unlock Mac"],
            shortTitle: "intent_unlock_mac_short_title",
            systemImageName: "lock.open.fill"
        )
    }
}
