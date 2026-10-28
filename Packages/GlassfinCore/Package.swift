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
    // The Linux toolchain has no xcstringstool. Exclude the catalog and copy a marker
    // so SwiftPM still generates Bundle.module for the shared catalog localization helper.
    let coreModelsExclude = ["Localizable.xcstrings"]
    let coreModelsResources: [Resource] = [.copy("LinuxStringCatalogMarker.txt")]
#else
    let packageDependencies = externalDependencies
    let coreAPIExternal: [Target.Dependency] = [
        // Identity is the repository name. The manifest's `name` is "JellyfinAPI", which
        // SwiftPM does not accept in `.product(package:)`.
        .product(name: "JellyfinAPI", package: "jellyfin-sdk-swift"),
        .product(name: "Get", package: "Get"),
    ]
    let coreModelsExclude = ["LinuxStringCatalogMarker.txt"]
    let coreModelsResources: [Resource] = [.process("Localizable.xcstrings")]
#endif

let debugSettings: [SwiftSetting] = [
    .define("DEBUG", .when(configuration: .debug))
]

let package = Package(
    name: "GlassfinCore",
    defaultLocalization: "en",
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
        .target(
            name: "CoreModels",
            exclude: coreModelsExclude,
            resources: coreModelsResources,
            swiftSettings: debugSettings
        ),
        .target(
            name: "CoreNetworking",
            dependencies: ["CoreModels"],
            swiftSettings: debugSettings
        ),
        // GlassfinServices, not CoreServices: that module name collides with the system
        // CoreServices framework Foundation imports, and `swift test` on macOS then
        // reports a Foundation -> CoreServices -> CoreModels cycle.
        .target(
            name: "GlassfinServices",
            dependencies: ["CoreModels", "CoreNetworking"],
            path: "Sources/CoreServices",
            swiftSettings: debugSettings
        ),
        .target(
            name: "CoreAPI",
            dependencies: ["CoreModels", "CoreNetworking", "GlassfinServices"] + coreAPIExternal,
            swiftSettings: debugSettings
        ),
        .target(
            name: "CoreState",
            dependencies: ["CoreModels", "CoreNetworking", "GlassfinServices"],
            swiftSettings: debugSettings
        ),
        .target(name: "CorePlayback", dependencies: ["CoreModels", "CoreNetworking"], swiftSettings: debugSettings),
        .target(
            name: "CoreTestSupport",
            dependencies: ["CoreModels", "CoreNetworking", "GlassfinServices", "CorePlayback"],
            swiftSettings: debugSettings
        ),
        .target(
            name: "GlassfinCore",
            dependencies: [
                "CoreModels",
                "CoreNetworking",
                "GlassfinServices",
                "CoreAPI",
                "CoreState",
                "CorePlayback",
                "CoreTestSupport",
            ],
            swiftSettings: debugSettings
        ),
        .testTarget(name: "CoreModelsTests", dependencies: ["CoreModels"]),
        .testTarget(
            name: "CoreStateTests",
            dependencies: [
                "CoreState", "CoreModels", "CoreNetworking", "GlassfinServices", "CoreTestSupport",
            ]
        ),
        .testTarget(name: "CoreNetworkingTests", dependencies: ["CoreNetworking", "CoreModels"]),
        .testTarget(
            name: "CoreServicesTests",
            dependencies: ["GlassfinServices", "CoreNetworking", "CoreModels", "CoreTestSupport", "CorePlayback"]
        ),
        .testTarget(
            name: "CorePlaybackTests",
            dependencies: ["CorePlayback", "CoreModels", "CoreNetworking", "CoreTestSupport"]
        ),
        .testTarget(
            name: "IntegrationTests",
            dependencies: ["CoreNetworking", "GlassfinServices", "CoreModels", "CorePlayback"]
        ),
    ]
)
