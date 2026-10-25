# Architecture

Runtime shape, code layout and data flow of MovingPaper; the rules that constrain changes are in `AGENTS.md`.

## Stack

A SwiftPM macOS menu-bar app for macOS 15 and later on Apple Silicon, written in Swift 6.
AppKit owns the wallpaper views and the status item; SwiftUI owns only the app lifecycle and the loading overlay.
AVFoundation plays video (`AVQueuePlayer`, `AVPlayerLooper`, `AVPlayerLayer`), ImageIO animates GIFs (`CGAnimateImageAtURLWithBlock`), PhotosUI and PhotoKit supply the Photos picker and shuffle, and private CoreGraphics APIs (`CGSCopyManagedDisplaySpaces`, `CGSGetActiveSpace`) track Spaces.
Sparkle 2.10.0 is vendored for updates; distribution is a notarized DMG and a Homebrew Cask ([05-infrastructure.md](05-infrastructure.md)).

## How the wallpaper is drawn

A borderless `NSPanel` (`WallpaperPanel`) sits at `desktopWindow + 1`, above the system wallpaper and below Finder icons, with `ignoresMouseEvents = true` so the desktop stays interactive.
`VideoWallpaperView` loops video and `GIFWallpaperView` animates GIFs with native frame timing.
Clip and Space changes reuse the on-screen panel so the system desktop never flashes through.
`ManagedDisplaySpaces` reads macOS's managed display-space snapshot, with a `CGSGetActiveSpace` fallback, so each display's active Space is known even when displays keep separate Spaces.
`WallpaperWindowController` owns one panel per display and pauses playback while a fullscreen app occludes it.

## Coordinator and seams

`WallpaperManager` is the coordinator, and each extracted helper owns one seam:

| Seam                 | Type                                          | Owns                                                                                           |
| -------------------- | --------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| Routing              | `WallpaperWindowRouter`                       | Hosts video and GIF directly in AppKit, never back through SwiftUI                             |
| Persistence          | `WallpaperPersistenceStore`                   | Saved wallpapers per display and Space, with versioned migrations covered by tests             |
| Presentation         | `AppPresentation`                             | Activation policy: accessory by default, foregrounded for Sparkle UI, restored afterwards      |
| Cache cleanup        | `CacheJanitor`                                | Evicts cached media; every enrolled cache needs a recovery story for an evicted file           |
| Power state          | `PowerStateMonitor`                           | Pauses in place on Low Power Mode and thermal throttling                                       |
| Request cancellation | `WallpaperRequestCoordinator`                 | The newest user choice wins; stale YouTube and Photos results are cancelled or ignored         |
| Serialization        | `AsyncSerialGate`                             | FIFO async mutex that serializes downloads                                                     |

`WallpaperState` and `WallpaperTypes` hold the model; `AppPaths` resolves the cache and support directories; `Log` wraps unified logging.

## Sources

- YouTube: `YouTubeURLParser` validates the URL, `YTDLPInstaller` pins, verifies and installs yt-dlp, and `YouTubeDownloader` runs it through the serial gate.
- Photos: `PhotosPickerController` wraps `PHPickerViewController`, and `PhotosService` picks a random video for Shuffle; the picker never returns a cache path when the file copy failed.
- Files: `.mp4`, `.mov`, `.m4v` and `.gif`, chosen through the status menu.
- `videos/` ships sample wallpapers for trying the app.

## Status item and menu

`StatusBarController` builds the menu from `MenuSnapshot`, so tests cover labels without launching the wallpaper app.
`MenuBarIcon` draws the template `cloud.moon.fill` symbol and `MenuBarLabelFormatter` formats item titles.
`OpenAtLogin` manages the login item, and `MovingPaperUpdater` drives Sparkle with every entry point foregrounding the accessory app and returning it to accessory on finish.
`MovingPaperApp` keeps a hidden `Settings { EmptyView() }` scene for lifecycle only and replaces `.appSettings` with an empty command group.
`AppIdentity` carries the production bundle identifier `com.8bittts.movingpaper`, and `AppIdentityDefaultsMigration` migrates defaults written under earlier identities.

## Modes

All Desktops applies one wallpaper everywhere; Per Desktop gives each Space and monitor its own, following per-display Space changes.
Playback is muted by default, pauses and resumes from the menu, and persists across relaunch.

## Build pipeline

`swift build` and `swift test` validate the package; `./scripts/build_and_run.sh` stages a real `.app` under `build/local-run/` because Sparkle stays dormant under `swift run`.
`Package.swift` anchors the Sparkle search and rpath flags to the manifest, so they resolve under Swift 6.4's default `swiftbuild` system (`.build/out`) and under `--build-system native`.
Release packaging, signing and distribution are [05-infrastructure.md](05-infrastructure.md); the gates are [09-quality.md](09-quality.md).
