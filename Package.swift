// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ObsidianPilot",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.4.0"),
    ],
    targets: [
        .executableTarget(
            name: "ObsidianPilot",
            dependencies: [
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
            ],
            path: "ObsidianPilot",
            exclude: ["Info.plist", "ObsidianPilot.entitlements"],
            resources: [
                .process("Assets.xcassets")
            ]
        )
    ]
)
