// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "OneLine",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "OneLine",
            resources: [
                .copy("Resources/RobotoMono-VariableFont_wght.ttf")
            ]
        )
    ]
)
