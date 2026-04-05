// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MovingPaper",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .executable(name: "MovingPaper", targets: ["MovingPaper"]),
    ],
    targets: [
        .executableTarget(
            name: "MovingPaper",
            path: "Sources/MovingPaper",
            resources: [
                .copy("Resources"),
            ]
        ),
    ]
)
