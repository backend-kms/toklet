// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "mac-note",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "MacNote", targets: ["MacNote"])],
    targets: [.executableTarget(name: "MacNote", linkerSettings: [.linkedFramework("Carbon")])]
)
