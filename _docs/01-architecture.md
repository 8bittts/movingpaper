# Architecture

Runtime shape, code layout and data flow of MovingPaper; the rules that constrain changes are in `AGENTS.md`.

## Stack

A SwiftPM macOS menu-bar app for macOS 27 and later on Apple Silicon, written in Swift 6.
The deployment target is the current system on purpose: the code carries no availability checks and no fallbacks for earlier releases.
AppKit owns the wallpaper views, the status item and the loading overlay's surface; SwiftUI owns only the app lifecycle and the overlay's content ([02-design-system.md](02-design-system.md)).
AVFoundation plays video (`AVQueuePlayer`, `AVPlayerLooper`, `AVPlayerLayer`), ImageIO animates GIFs (`CGAnimateImageAtURLWithBlock`), PhotosUI and PhotoKit supply the Photos picker and shuffle, and private CoreGraphics APIs (`CGSCopyManagedDisplaySpaces`, `CGSGetActiveSpace`) track Spaces.
Sparkle 2.10.1 is vendored for updates; distribution is a notarized DMG and a Homebrew Cask ([05-infrastructure.md](05-infrastructure.md)).

## How the wallpaper is drawn

A borderless `NSPanel` (`WallpaperPanel`) sits at `desktopWindow + 1`, above the system wallpaper and below Finder icons, with `ignoresMouseEvents = true` so the desktop stays interactive.
`VideoWallpaperView` loops video and `GIFWallpaperView` animates GIFs with native frame timing; both conform to `WallpaperContentView`, whose one requirement is an idempotent `isPlaybackPaused`.
Each view keeps the pause as state, so a pause that arrives before the media has loaded still holds: a video stays on its first frame and a GIF shows its first frame without animating.
Clip and Space changes reuse the on-screen panel so the system desktop never flashes through.
`ManagedDisplaySpacesSnapshot` (`sources/ManagedDisplaySpaces.swift`) reads macOS's managed display-space snapshot, with a `CGSGetActiveSpace` fallback, so each display's active Space is known even when displays keep separate Spaces.
`WallpaperWindowController` owns one panel per display and pauses its content while a fullscreen app occludes it or `PowerStateMonitor` reports Low Power Mode or thermal pressure.
Only `didChangeOcclusionStateNotification` updates the occlusion flag: a panel reads as not visible until the window server reports back, so a fresh panel is treated as visible.
A video that cannot be loaded or played, and a GIF ImageIO rejects, reach `WallpaperManager` through `onFailure`, which alerts once per file.

## Coordinator and seams

`WallpaperManager` is the coordinator, and each extracted helper owns one seam:

| Seam                 | Type                          | Owns                                                                                      |
| -------------------- | ----------------------------- | ----------------------------------------------------------------------------------------- |
| Routing              | `WallpaperWindowRouter`       | Hosts video and GIF directly in AppKit, never back through SwiftUI                        |
| Persistence          | `WallpaperPersistenceStore`   | Saved wallpapers per display and Space, with versioned migrations covered by tests        |
| Presentation         | `AppPresentation`             | Activation policy: accessory unless a surface holds a reason (modal, Photos picker, shuffle, Sparkle session, Dock session); regular until the last hold ends |
| Cache cleanup        | `CacheJanitor`                | Evicts cached media; every enrolled cache needs a recovery story for an evicted file      |
| Power state          | `PowerStateMonitor`           | Pauses in place on Low Power Mode and thermal throttling                                  |
| Request cancellation | `WallpaperRequestCoordinator` | The newest user choice wins; stale YouTube and Photos results are canceled or ignored     |
| Serialization        | `AsyncSerialGate`             | FIFO async mutex that serializes downloads                                                |

A saved playback position belongs to the file that was playing: assigning a different file to a desktop drops it.
Saved wallpapers carry the display UUID (schema v2) beside the display ID, because a display ID can change across a restart; loading maps the UUID back to the connected display's current ID.
Requests are keyed by desktop: in Per Desktop mode each Space of a display is its own target, so a request on one Space does not cancel another Space's download.
Launch-time cache cleanup skips files modified after launch, which belong to work the session already started.

`WallpaperState` and the `WallpaperMode`, `DesktopKey` and `WallpaperFileType` types in `sources/WallpaperTypes.swift` hold the model; `AppPaths` resolves the cache and support directories; `Log` wraps unified logging.

## Sources

- YouTube: `YouTubeURLParser` validates the URL, `YTDLPInstaller` pins, verifies and installs yt-dlp, and `YouTubeDownloader` runs it through the serial gate.
  A download reports its fraction to a per-call progress handler and `nil` when it ends, so the overlay follows the display the download is for; `cancel()` stops the running download only.
  A subprocess run ends when the process has exited and stderr has reached its end, joined by a `DispatchGroup` with no blocking wait; a launch failure settles both itself, because neither event arrives for a process that never started.
- Photos: `PhotosPickerController` wraps `PHPickerViewController`, and the stateless `PhotosService` picks a random video for Shuffle and returns a typed `PhotosShuffleFailure` otherwise; the picker never returns a cache path when the file copy failed.
  A shuffle export writes to a file of its own and moves it into place, so a file at the cache path is always complete; canceling resumes the export-session wait itself, because PhotoKit promises a cancel callback only for image requests.
- Files: `.mp4`, `.mov`, `.m4v` and `.gif`, chosen through the status menu.
- `videos/` ships sample wallpapers for trying the app.

## Status item and menu

`StatusBarController` builds the menu from `MenuSnapshot`, so tests cover labels without launching the wallpaper app.
`MenuBarIcon` supplies the app's own icon at menu-bar size and `MenuBarLabelFormatter` formats item titles.
`OpenAtLogin` manages the login item; a login item waiting on approval shows `Allow Open at Login…` and opens the Login Items settings, because registering again fails until the user approves it.
`MovingPaperUpdater` drives Sparkle; every entry point holds the `.updater` presentation reason once per session and the session finish ends it.
Opening the app while it runs starts a Dock session: a Dock icon whose menu is the status menu without Quit, ended when the status menu closes.
The menu is rebuilt each time it opens, so it reads `canCheckForUpdates` and the download fraction directly; nothing publishes them.
`MovingPaperApp` keeps a hidden `Settings { EmptyView() }` scene for lifecycle only and replaces `.appSettings` with an empty command group.
`AppIdentity` carries the production bundle identifier `com.8bittts.movingpaper`, and `AppIdentityDefaultsMigration` migrates defaults written under earlier identities.

## Modes

All Desktops applies one wallpaper everywhere; Per Desktop gives each Space and monitor its own, following per-display Space changes.
Playback is muted by default, pauses and resumes from the menu, and persists across relaunch.

## Build pipeline

`swift build` and `swift test` validate the package; `./scripts/build_and_run.sh` stages a real `.app` under `build/local-run/` because Sparkle stays dormant under `swift run`.
`Package.swift` anchors the Sparkle search and rpath flags to the manifest, so they resolve under Swift 6.4's default `swiftbuild` system (`.build/out`) and under `--build-system native`.
Release packaging, signing and distribution are [05-infrastructure.md](05-infrastructure.md); the gates are [09-quality.md](09-quality.md).
