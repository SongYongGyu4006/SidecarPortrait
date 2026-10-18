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
        // 가로 Sidecar 화면에 띄우는 Claude·Gemini 사용량 대시보드
        .executableTarget(
            name: "UsageDashboard",
            dependencies: ["PrivateAPI"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
