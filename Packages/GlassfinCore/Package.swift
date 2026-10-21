// swift-tools-version: 6.2
import PackageDescription

// jellyfin-sdk-swift depends on NIOTransportServices (Network.framework) and does not
// build on Linux. The dependency stays declared so Package.resolved is pinned, but only
// the CoreAPI target links it, and only when the manifest is evaluated off Linux.
let externalDependencies: [Package.Dependency] = [
    .package(url: "https://github.com/jellyfin/jellyfin-sdk-swift.git", from: "3.3.0"),
    .package(url: "https://github.com/kean/Get.git", from: "2.1.6"),
]

#if os(Linux)
    // Declared so `swift package resolve` can pin jellyfin-sdk-swift, but not linked:
    // NIOTransportServices needs Network.framework and does not build on Linux.
    let packageDependencies = externalDependencies
    let coreAPIExternal: [Target.Dependency] = []
#else
    let packageDependencies = externalDependencies
    let coreAPIExternal: [Target.Dependency] = [
        // Identity is the repository name. The manifest's `name` is "JellyfinAPI", which
        // SwiftPM does not accept in `.product(package:)`.
        .product(name: "JellyfinAPI", package: "jellyfin-sdk-swift"),
        .product(name: "Get", package: "Get"),
    ]
#endif

let debugSettings: [SwiftSetting] = [
    .define("DEBUG", .when(configuration: .debug))
]

let package = Package(
    name: "GlassfinCore",
    platforms: [
        .iOS(.v26),
        .tvOS(.v26),
        .macOS(.v26),
    ],
    products: [
        .library(name: "GlassfinCore", targets: ["GlassfinCore"])
    ],
    dependencies: packageDependencies,
    targets: [
        .target(name: "CoreModels", swiftSettings: debugSettings),
        .target(name: "CoreNetworking", dependencies: ["CoreModels"], swiftSettings: debugSettings),
        .target(name: "CoreServices", dependencies: ["CoreModels", "CoreNetworking"], swiftSettings: debugSettings),
        .target(
            name: "CoreAPI",
            dependencies: ["CoreModels", "CoreNetworking", "CoreServices"] + coreAPIExternal,
            swiftSettings: debugSettings
        ),
        .target(name: "CoreState", dependencies: ["CoreModels"], swiftSettings: debugSettings),
        .target(name: "CorePlayback", dependencies: ["CoreModels", "CoreNetworking"], swiftSettings: debugSettings),
        .target(
            name: "CoreTestSupport",
            dependencies: ["CoreModels", "CoreNetworking", "CoreServices"],
            swiftSettings: debugSettings
        ),
        .target(
            name: "GlassfinCore",
            dependencies: [
                "CoreModels",
                "CoreNetworking",
                "CoreServices",
                "CoreAPI",
                "CoreState",
                "CorePlayback",
                "CoreTestSupport",
            ],
            swiftSettings: debugSettings
        ),
        .testTarget(name: "CoreModelsTests", dependencies: ["CoreModels"]),
        .testTarget(name: "CoreNetworkingTests", dependencies: ["CoreNetworking", "CoreModels"]),
        .testTarget(
            name: "CoreServicesTests",
            dependencies: ["CoreServices", "CoreNetworking", "CoreModels", "CoreTestSupport", "CorePlayback"]
        ),
        .testTarget(
            name: "IntegrationTests",
            dependencies: ["CoreNetworking", "CoreServices", "CoreModels"]
        ),
    ]
)
