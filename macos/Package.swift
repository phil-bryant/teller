// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TransactionClassifier",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "TransactionClassifier", targets: ["TransactionClassifier"])],
    targets: [
        .executableTarget(name: "TransactionClassifier"),
        .testTarget(name: "TransactionClassifierTests", dependencies: ["TransactionClassifier"]),
    ]
)
