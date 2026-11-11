# Foundation

History, decisions and the audit closure record for MovingPaper; every other doc describes the code as it is.

## Timeline

Dates are the evidence in this doc; the owner docs carry none.

- 2026-04-04: the initial commit and the first releases, v0.002 through v0.008, ship in one day, including per-desktop wallpapers across Spaces and the brand icon in the menu bar.
- 2026-04-05: v0.009 through v0.018 add styled Sparkle release notes generated from git history, auto-tagging, Sparkle windows above all windows, and the fix for Photos shuffle hangs and the authorization prompt.
- 2026: a source audit of `sources/` (about 3,081 lines) fixes 34 findings and grows the suite from 79 to 101 tests; its record is below.
- 2026: the HIG menu-bar extra pass (#30 to #43) lands; its deferred follow-ups stay in `todos.md`.
- 2026-11-10: a second source audit and refactor of `sources/` lands; its record is below.
- 2026-11-10: the loading overlay moves to Liquid Glass and the interface copy is normalized, closing HIG follow-up #47.
- 2026-11-10: the deployment target moves from macOS 15 to macOS 27; v0.044 is the last release for macOS 15 through 26.
- 2026-11-10: the app icon becomes an Icon Composer document, closing HIG follow-up #45; the iconset pipeline and the run-time icon override are removed.
- 2026-11-10: the menu-bar extra returns to the brand mark, now the system-rendered app icon in place of the template symbol the HIG pass introduced.

## Decisions

- **Dockless by design.** The app is an accessory (`LSUIElement`) with no Dock icon during normal use, update checks or install prompts; the Dock-fallback HIG item is deferred unless an explicit Show Dock Icon command is added.
- **No visible Settings surface** until a real preferences UI exists; `AGENTS.md` carries the rule.
- **Exact pins for what the app downloads.** yt-dlp is pinned by version and SHA-256 and Sparkle by version, build and binary hash ([04-security.md](04-security.md)).
- **One doc set for the two macOS apps.** dockishOS owns the Sparkle re-vendor procedure and MovingPaper cites it; MovingPaper's own release path lives in [05-infrastructure.md](05-infrastructure.md) rather than in a root build document or the README.
- **The menu-bar extra is branded.** The HIG prefers a template glyph, and the HIG pass used one; the operator chose the color app icon so the status item is recognizable as MovingPaper while it runs.
- **macOS 27 only.** The app adopts the current system design without fallbacks, so the pre-26 HUD-material overlay and every availability check are gone. The cost is accepted: Macs on macOS 15 through 26 stay on v0.044, and CI can only compile until a hosted macOS 27 runner exists.
- **System surfaces over brand chrome.** The loading overlay was a night-sky brand pill with a shimmer; it is now Liquid Glass with system text styles, and the brand stays in the app icon and the menu-bar mark ([02-design-system.md](02-design-system.md)).
- **The release script pins the Homebrew Cask.** The Cask was bumped by hand through v0.044 and trailed by up to five releases; `bump_cask` now runs inside the release commit ([05-infrastructure.md](05-infrastructure.md)).

## Audit closure (2026)

Historical source audit of `sources/` (about 3,081 LOC); every change was gated on `swift build` and `swift test`.
34 findings were fixed and the suite grew from 79 to 101 tests.

### Done (shipped to `main`)

Correctness and data loss:

- #3: pending YouTube redownloads were re-persisted on every save, which was permanent data loss on cache eviction.
- #1: the restore-redownload batch is no longer aborted by unrelated local, Photos or clear actions.
- #11 and #28: downloads are serialized through `AsyncSerialGate`, a FIFO async mutex.
- #2 and #8: `download` returns a per-call `DownloadOutcome`.
- #7: a "for all" pick in perDesktop mode now applies to every display.
- #9: mode collapse and reconcile pick a deterministic `canonicalEntry`.
- #14 and #43: the Photos picker never returns a cache path when the file copy failed.

Concurrency, security and robustness fixes #26, #4 and #27, #13, #12, #41, #10 and #44, #23, #15 and #34, and #42 are in git history (`177df9d..90a6358`).

### Closed as won't-fix

- #19 and #21, `AppPresentation` refcount: incompatible with the Sparkle lifecycle in `AGENTS.md`.
- #23, the ordering half: moot at launch-time eviction.
- #22, the hidden Settings scene: sanctioned in `AGENTS.md`.
- #20, menu builder extract: already decomposed sufficiently.
- #16, #30 and #31: see the original audit rationale in git history.

## Second audit (2026-11-10)

A refactor and audit of `sources/` against Apple's developer documentation; every change was gated on `swift build -Xswiftc -warnings-as-errors`, `swift test` and Periphery.
The suite grew from 133 to 144 tests.

Defects found and fixed, each reproduced first:

- A video loaded while paused started playing when its asset arrived, so Low Power Mode at launch did not pause the wallpaper.
- A GIF restarted from its first frame on every reconcile, which is every Space switch in Per Desktop mode.
- An unplayable video reported nothing and left a black panel.
- The menu-bar symbol was forced to 18 by 18 points and drew about 29% too tall.
- The progress overlay followed the newest YouTube request, not the display whose download was running.
- A restore redownload canceled from the menu was counted as a failure.
- yt-dlp's closing `ERROR:` line could be lost when the process exited while a stderr read was in flight, leaving the generic "Download failed"; a run now ends only when the process has exited and stderr has ended.
- A second Choose from Photos request returned the app to accessory while the first picker was open.

Removed as dead or redundant: the Combine pipelines in `YouTubeDownloader` and `MovingPaperUpdater`, the downloader's canceled-ID set, the lock around the GIF generation counter (ImageIO documents the frame block as running on the main queue), the `OcclusionPausable` protocol and its static forwarder, a bundled PNG that no code loaded, and unreachable branches in the Spaces parser, the URL parser and the window router.

Decisions:

- **The wallpaper view types take the names of their files**, `VideoWallpaperView` and `GIFWallpaperView`.
- **Occlusion is notification-driven only.** A probe showed `occlusionState` reads as not visible right after `orderFront` even for a window that is about to appear, so sampling it there paused content the old views then started anyway.
- **`activate()` replaces `activate(ignoringOtherApps:)`**, which Apple deprecated; its flag has had no effect since macOS 14.

Left as they are, on purpose: the hidden `Settings` scene (`AGENTS.md`), the non-opaque black `WallpaperPanel` (unverifiable without a runtime check), the caches under Application Support, and `Info.plist` inside the SwiftPM resource directory (four scripts read that path).
