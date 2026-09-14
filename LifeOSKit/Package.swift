// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LifeOSKit",
    platforms: [.iOS("26.0"), .macOS("26.0"), .watchOS("26.0")],
    products: [
        .library(name: "AppSurfaces", targets: ["AppSurfaces"]),
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
        .library(name: "Persistence", targets: ["Persistence"]),
        .library(name: "Integrations", targets: ["Integrations"]),
        .library(name: "Insights", targets: ["Insights"]),
        .library(name: "Sectors", targets: ["Sectors"]),
        .library(name: "Assistant", targets: ["Assistant"]),
    ],
    targets: [
        .target(name: "AppSurfaces"),
        .testTarget(name: "AppSurfacesTests", dependencies: ["AppSurfaces"]),
        .target(name: "DesignSystem"),
        .target(name: "Persistence"),
        .target(name: "Integrations", dependencies: ["Persistence", "AppSurfaces"]),
        .target(name: "Insights", dependencies: ["Persistence"]),
        .target(name: "Sectors", dependencies: ["Persistence"]),
        .target(name: "Assistant", dependencies: ["Insights", "Persistence"]),
        .testTarget(name: "DesignSystemTests", dependencies: ["DesignSystem"]),
        .testTarget(name: "PersistenceTests", dependencies: ["Persistence"]),
        .testTarget(name: "IntegrationsTests", dependencies: ["Integrations"]),
        .testTarget(name: "InsightsTests", dependencies: ["Insights"]),
        .testTarget(name: "SectorsTests", dependencies: ["Sectors"]),
        .testTarget(name: "AssistantTests", dependencies: ["Assistant"]),
    ]
)
