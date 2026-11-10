# Quality

Gates, test strategy, static analysis and verification rules for MovingPaper.

## Gates

`swift test` runs the unit suite in `tests/`, and `./scripts/smoke-test.sh` is the pre-ship gate: it runs the tests, builds release, assembles a staged app bundle and verifies the bundle shape without launching the wallpaper.
`./scripts/smoke-test.sh --production` also requires and verifies the signed release app, the signed and notarized DMG, the checksum and the signed Sparkle appcast, and the release flow runs it as its production gate.
CI only compiles the app and its tests; it cannot run them until a hosted runner runs macOS 27 ([05-infrastructure.md](05-infrastructure.md)).

## Test strategy

Wallpaper runtime actions are real side effects: they mutate the desktop wallpaper, request Photos access and start downloads.
Prefer source inspection and non-launching checks over clicking menu actions.
The status-menu structure lives in `MenuSnapshot`, so tests cover menu labels without launching the app.
`VideoWallpaperView` and `GIFWallpaperView` are tested without a window against the sample media in `videos/`, so no wallpaper appears on the desktop.
`YouTubeDownloader` takes its cache directory and binary resolver by injection; its tests run a shell script in place of yt-dlp, which covers progress, failure, launch failure, cancel, task cancellation and the queue with no network.
A `WallpaperPersistenceStore` schema change is not done until a test covers the new migration path.
Mutation-test a new guard by breaking what it protects and watching it fail.

## Static analysis

Periphery 3.8.0 (`.periphery.yml`) finds unused code; install the final 3.8.0 binary from its GitHub release because upstream is archived and the Homebrew cask is stale.
It passes `--build-system native` because Swift 6.4's default build system writes no index store where Periphery looks, and it retains public, `@objc`, protocol-parameter and assign-only declarations on purpose.
CI's toolchain and SDK (the `macos-26` runner) trail a macOS 27 Mac's, so a construct that only the newer compiler or SDK accepts passes locally and fails there.
Build with `-Xswiftc -warnings-as-errors` after raising the deployment target: each raise turns newly deprecated calls into warnings.

## Manual verification

The overlay can be checked without a wallpaper action: show `LoadingOverlayController` from a temporary test, capture that screen region with `screencapture -x -R`, and read the image.
Use `./scripts/build_and_run.sh --logs` for anything that touches Sparkle, the loading overlay or per-display Space tracking, and confirm the behavior on more than one display when a change touches Spaces.
Open items that still need a runtime check live in `todos.md`.
