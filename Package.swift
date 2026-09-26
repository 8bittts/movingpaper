// swift-tools-version: 6.0
import Foundation
import PackageDescription

// [CRITICAL] The Sparkle framework search path must be ABSOLUTE.
//
// `-F tools/sparkle` was relative, which only resolved while the compiler inherited the package
// root as its working directory. Swift 6.4 / Xcode 27 build through the Xcode build engine
// (`.build/manifest.pif`, `.build/out/Intermediates.noindex`), and that engine passes
// `-working-directory <parent of the package>` to swiftc. The relative path then resolved to
// `../tools/sparkle`, which does not exist, and every build failed with
// `unable to resolve module dependency: 'Sparkle'` even though the vendored framework was intact
// and matched its VERSION pin.
//
// Anchor to this manifest instead of to a working directory nothing here controls. `#filePath` is
// the absolute path of this file, so the search path follows the checkout — including a worktree
// at a different path — and never depends on where the build is launched from.
//
// Both targets need it: the executable and the test target each pass the flag twice, once to the
// compiler and once to the linker. The `@rpath` entries below stay relative on purpose — they are
// resolved at load time against the built binary, not at compile time against a working directory.
let sparkleSearchPath = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("tools/sparkle")
    .path

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
            path: "sources",
            resources: [
                .copy("Resources"),
            ],
            swiftSettings: [
                .unsafeFlags([
                    "-F",
                    sparkleSearchPath,
                ]),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-F",
                    sparkleSearchPath,
                    "-framework",
                    "Sparkle",
                    "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks",
                    "-Xlinker", "-rpath", "-Xlinker", "@loader_path/../Frameworks",
                    "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../../../tools/sparkle",
                    "-Xlinker", "-rpath", "-Xlinker", "@loader_path/../../../tools/sparkle",
                ]),
            ]
        ),
        .testTarget(
            name: "MovingPaperTests",
            dependencies: ["MovingPaper"],
            path: "tests",
            swiftSettings: [
                .unsafeFlags([
                    "-F",
                    sparkleSearchPath,
                ]),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-F",
                    sparkleSearchPath,
                    "-framework",
                    "Sparkle",
                    "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks",
                    "-Xlinker", "-rpath", "-Xlinker", "@loader_path/../Frameworks",
                    // The test bundle is never shipped, so it may carry an absolute rpath. It has to:
                    // the relative hop below counted directories in the old `.build/debug` layout, and
                    // the Xcode build engine nests the bundle deeper under `.build/out/Products/Debug`,
                    // so the hop landed on `.build/out/tools/sparkle` and dyld failed to load Sparkle.
                    "-Xlinker", "-rpath", "-Xlinker", sparkleSearchPath,
                    "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../../../../../../tools/sparkle",
                    "-Xlinker", "-rpath", "-Xlinker", "@loader_path/../../../../../../tools/sparkle",
                ]),
            ]
        ),
    ]
)
