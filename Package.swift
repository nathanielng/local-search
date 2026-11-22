// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LocalSearch",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "FinderCore", targets: ["FinderCore"]),
        .executable(name: "LocalSearch", targets: ["LocalSearch"]),
        .executable(name: "local-search-mcp", targets: ["local-search-mcp"]),
    ],
    targets: [
        .target(name: "FinderCore"),
        .executableTarget(name: "LocalSearch", dependencies: ["FinderCore"]),
        .executableTarget(name: "local-search-mcp", dependencies: ["FinderCore"]),
        .testTarget(name: "FinderCoreTests", dependencies: ["FinderCore"]),
    ]
)
