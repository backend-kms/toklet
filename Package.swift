// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Toklet",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Toklet", targets: ["Toklet"])],
    targets: [
        .executableTarget(name: "Toklet", linkerSettings: [.linkedFramework("Carbon")]),
        .testTarget(name: "TokletTests", dependencies: ["Toklet"])
    ]
)
