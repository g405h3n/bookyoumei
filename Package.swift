// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "bookmarknot",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "BookmarkModel"),
        .target(name: "ChromeConnector", dependencies: ["BookmarkModel"]),
        .target(name: "SafariConnector", dependencies: ["BookmarkModel"]),
        .target(name: "Store", dependencies: ["BookmarkModel"]),
        .target(name: "MergeEngine", dependencies: ["BookmarkModel"]),
        .testTarget(name: "BookmarkModelTests", dependencies: ["BookmarkModel"]),
        .testTarget(name: "ChromeConnectorTests", dependencies: ["ChromeConnector"],
                    resources: [.copy("Fixtures")]),
        .testTarget(name: "SafariConnectorTests", dependencies: ["SafariConnector"],
                    resources: [.copy("Fixtures")]),
        .testTarget(name: "StoreTests", dependencies: ["Store"]),
        .testTarget(name: "MergeEngineTests", dependencies: ["MergeEngine"]),
    ]
)
