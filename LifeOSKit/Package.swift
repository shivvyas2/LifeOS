// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LifeOSKit",
    platforms: [.iOS("26.0"), .macOS("26.0")],
    products: [
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
        .library(name: "Persistence", targets: ["Persistence"]),
    ],
    targets: [
        .target(name: "DesignSystem"),
        .target(name: "Persistence"),
        .testTarget(name: "DesignSystemTests", dependencies: ["DesignSystem"]),
        .testTarget(name: "PersistenceTests", dependencies: ["Persistence"]),
    ]
)
