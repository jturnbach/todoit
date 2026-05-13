// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TodoIt",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "TodoIt", targets: ["TodoIt"]),
        .executable(name: "todoit", targets: ["todoitcli"])
    ],
    targets: [
        .target(
            name: "TodoItCore",
            path: "Sources/TodoItCore"
        ),
        .executableTarget(
            name: "TodoIt",
            dependencies: ["TodoItCore"],
            path: "Sources/TodoIt"
        ),
        .executableTarget(
            name: "todoitcli",
            dependencies: ["TodoItCore"],
            path: "Sources/todoit-cli"
        )
    ]
)
