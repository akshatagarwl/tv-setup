// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "TVSetupCore", platforms: [.iOS(.v16), .macOS(.v13)],
    products: [.library(name: "TVSetupCore", targets: ["TVSetupCore"])],
    dependencies: [.package(path: "../vendor/SwiftADB")],
    targets: [
        .target(name: "TVSetupCore", dependencies: ["SwiftADB"], resources: [.copy("Resources/catalog.json"), .copy("Resources/search-handoff-1.0.apk"), .copy("Resources/NOTICES.txt")]),
        .testTarget(name: "TVSetupCoreTests", dependencies: ["TVSetupCore", "SwiftADB"])
    ], swiftLanguageModes: [.v5]
)
