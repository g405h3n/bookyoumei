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
        .target(
            name: "SyncEngine",
            dependencies: ["BookmarkModel", "ChromeConnector", "SafariConnector", "Store", "MergeEngine"]
        ),
        .target(name: "WatcherEngine", dependencies: ["SyncEngine"]),
        .testTarget(name: "BookmarkModelTests", dependencies: ["BookmarkModel"]),
        .testTarget(name: "ChromeConnectorTests", dependencies: ["ChromeConnector"],
                    resources: [.copy("Fixtures")]),
        .testTarget(name: "SafariConnectorTests", dependencies: ["SafariConnector"],
                    resources: [.copy("Fixtures")]),
        .testTarget(name: "StoreTests", dependencies: ["Store"]),
        .testTarget(name: "MergeEngineTests", dependencies: ["MergeEngine"]),
        .testTarget(name: "SyncEngineTests", dependencies: ["SyncEngine"]),
        .testTarget(name: "WatcherEngineTests", dependencies: ["WatcherEngine"]),
    ]
)
