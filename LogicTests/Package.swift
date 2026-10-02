// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "MacRemoteLogic",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "ServerUnlockLogic"),
        .target(name: "ClientUnlockLogic"),
        .testTarget(name: "ServerUnlockLogicTests", dependencies: ["ServerUnlockLogic"]),
        .testTarget(name: "ClientUnlockLogicTests", dependencies: ["ClientUnlockLogic"]),
    ],
    swiftLanguageModes: [.v5]
)
