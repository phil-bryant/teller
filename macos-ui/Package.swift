// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TransactionClassifier",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "TransactionClassifier", targets: ["TransactionClassifier"])],
    dependencies: [
        .package(url: "https://github.com/microsoft/plcrashreporter.git", from: "1.12.0"),
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.17.0"),
    ],
    targets: [
        .executableTarget(
            name: "TransactionClassifier",
            dependencies: [
                .product(name: "CrashReporter", package: "plcrashreporter"),
            ]
        ),
        .testTarget(name: "TransactionClassifierTests", dependencies: ["TransactionClassifier"]),
        .testTarget(
            name: "TransactionClassifierSnapshotTests",
            dependencies: [
                "TransactionClassifier",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
            ],
            exclude: ["__Snapshots__"]
        ),
    ]
)
