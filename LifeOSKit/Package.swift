// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LifeOSKit",
    platforms: [.iOS("18.0"), .macOS("15.0")],
    products: [
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
        .library(name: "Persistence", targets: ["Persistence"]),
        .library(name: "Integrations", targets: ["Integrations"]),
    ],
    targets: [
        .target(name: "DesignSystem"),
        .target(name: "Persistence"),
        .target(name: "Integrations", dependencies: ["Persistence"]),
        .testTarget(name: "DesignSystemTests", dependencies: ["DesignSystem"]),
        .testTarget(name: "PersistenceTests", dependencies: ["Persistence"]),
        .testTarget(name: "IntegrationsTests", dependencies: ["Integrations"]),
    ]
)
