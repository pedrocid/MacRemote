import ProjectDescription

let project = Project(
    name: "MacRemoteClient",
    targets: [
        .target(
            name: "MacRemoteClient",
            destinations: [.iPhone, .iPad],
            product: .app,
            bundleId: "com.pedrocid.MacRemoteClient",
            deploymentTargets: .iOS("17.0"),
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "MacRemote",
                "UILaunchScreen": .dictionary([:]),
                "UISupportedInterfaceOrientations": .array([
                    "UIInterfaceOrientationPortrait",
                    "UIInterfaceOrientationLandscapeLeft",
                    "UIInterfaceOrientationLandscapeRight"
                ]),
                "UISupportedInterfaceOrientations~ipad": .array([
                    "UIInterfaceOrientationPortrait",
                    "UIInterfaceOrientationPortraitUpsideDown",
                    "UIInterfaceOrientationLandscapeLeft",
                    "UIInterfaceOrientationLandscapeRight"
                ]),
                "NSBonjourServices": .array(["_macremote._tcp"]),
                "NSLocalNetworkUsageDescription": "MacRemote needs access to the local network to find and connect to your Mac"
            ]),
            sources: [
                "Sources/**",
                "../Shared/**"
            ],
            resources: [],
            settings: .settings(
                base: [
                    "SWIFT_VERSION": "5.9",
                    "CODE_SIGN_STYLE": "Automatic"
                ]
            )
        )
    ]
)
