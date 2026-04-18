// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TellerReclassifier",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "TellerReclassifier", targets: ["TellerReclassifier"])],
    targets: [
        .executableTarget(name: "TellerReclassifier"),
        .testTarget(name: "TellerReclassifierTests", dependencies: ["TellerReclassifier"]),
    ]
)
