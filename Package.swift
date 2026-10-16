// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SidecarPortrait",
    platforms: [.macOS(.v15)],
    targets: [
        // CGVirtualDisplay·SidecarCore 비공개 API 래퍼
        .target(name: "PrivateAPI"),
        .executableTarget(
            name: "SidecarPortrait",
            dependencies: ["PrivateAPI"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
