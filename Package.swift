// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "bookmarknot",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "BookmarkModel"),
        .target(name: "ChromeConnector", dependencies: ["BookmarkModel"]),
        .testTarget(name: "ChromeConnectorTests", dependencies: ["ChromeConnector"],
                    resources: [.copy("Fixtures")]),
    ]
)
