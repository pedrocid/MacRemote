import ProjectDescription

let project = Project(
    name: "MacRemoteServer",
    targets: [
        .target(
            name: "MacRemoteServer",
            destinations: .macOS,
            product: .app,
            bundleId: "com.pedrocid.MacRemoteServer",
            deploymentTargets: .macOS("14.0"),
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "MacRemote Server",
                "LSUIElement": true,
                "NSHighResolutionCapable": true,
                "NSBonjourServices": .array(["_macremote._tcp"]),
                "NSLocalNetworkUsageDescription": "MacRemote uses the local network to communicate with iOS devices"
            ]),
            sources: [
                "Sources/**",
                "../Shared/**"
            ],
            resources: [],
            entitlements: .dictionary([
                "com.apple.security.app-sandbox": .boolean(false),
                "com.apple.security.network.server": .boolean(true),
                "com.apple.security.network.client": .boolean(true)
            ]),
            settings: .settings(
                base: [
                    "SWIFT_VERSION": "5.9",
                    "CODE_SIGN_STYLE": "Automatic",
                    "ENABLE_HARDENED_RUNTIME": "YES"
                ]
            )
        )
    ]
)
