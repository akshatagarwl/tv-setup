// swift-tools-version: 6.0
// TV Setup uses only the upstream packet codec and RSA/public-key primitives.
import PackageDescription
let package = Package(
    name: "SwiftADB",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [.library(name: "SwiftADB", targets: ["SwiftADB"])],
    dependencies: [
        .package(url: "https://github.com/attaswift/BigInt.git", exact: "5.7.0"),
        .package(url: "https://github.com/apple/swift-asn1.git", exact: "1.7.1")
    ],
    targets: [.target(name: "SwiftADB", dependencies: ["BigInt", .product(name: "SwiftASN1", package: "swift-asn1")])]
)
