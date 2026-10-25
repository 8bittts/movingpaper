# MovingPaper agent notes

## Orientation

SwiftPM macOS menu-bar app (`sources/`, `tests/`).
Validate with `swift test` and `./scripts/smoke-test.sh`; `--production` also verifies signing, notarization, checksum, and the signed appcast without launching the wallpaper app.
`Package.swift` anchors the Sparkle search and rpath flags to the manifest, so they resolve under both Swift 6.4's default `swiftbuild` system (`.build/out`) and `--build-system native`.
Periphery 3.8.0 is the exception: it finds no index store under `swiftbuild`, so `.periphery.yml` passes `--build-system native`.
The script matrix, release flow and CI are in [_docs/05-infrastructure.md](_docs/05-infrastructure.md); the gates are in [_docs/09-quality.md](_docs/09-quality.md).
Owner-doc index: [_docs/00-docs-map.md](_docs/00-docs-map.md), which follows the fleet documentation standard.

Sparkle work must go through `./scripts/build_and_run.sh`, which stages a real `.app` under `build/local-run/`.
`swift run MovingPaper` leaves Sparkle dormant.

Treat wallpaper runtime actions as real side effects.
Prefer source inspection and non-launching smoke checks over clicking menu actions that mutate the desktop wallpaper, request Photos access, or start downloads.
Status-menu structure lives in `MenuSnapshot`; tests cover labels without launching the wallpaper app.

## Constraints

- Keep the production bundle identifier `com.8bittts.movingpaper` and preserve `AppIdentityDefaultsMigration` when touching defaults or bundle metadata.
- Do not reintroduce a visible Settings surface.
  `MovingPaperApp` keeps a hidden `Settings { EmptyView() }` scene for lifecycle only and replaces `.appSettings` with an empty command group so Cmd-, cannot open a blank window.
  The menu must not advertise Settings until a real preferences UI exists.
- The menu-bar extra icon is a template SF Symbol (`cloud.moon.fill`).
  Keep the colour night-sky PNG for the app icon only; do not set `isTemplate = false` on the status item.
- `WallpaperManager` stays the coordinator; extracted helpers each own one seam (routing, persistence, presentation, cache cleanup, power state, request cancellation).
  Do not route wallpaper rendering back through SwiftUI — `WallpaperWindowRouter` hosts video/GIF directly in AppKit.
- A `WallpaperPersistenceStore` schema change is not done until a test covers the new migration path.
- New async wallpaper sources go through `WallpaperRequestCoordinator` so the newest user choice wins, and long-running subprocess or network work must cooperate with `withTaskCancellationHandler` so cancellation actually tears it down.
- Do not enroll a cache in `CacheJanitor` without a recovery story for an evicted file.
- `YTDLPInstaller` pins yt-dlp by version and hash — bump `pinnedVersion` and `pinnedSHA256` together.
  `YouTubeDownloader` exposes the same values as `pinnedYTDLPVersion` / `pinnedYTDLPSHA256`.
- The vendored Sparkle framework is pinned in `tools/sparkle/VERSION` (version, build, binary SHA-256, and `required_paths`), and the `scripts/build-dmg.sh` preflight fails the build when the framework drifts from the pin.
  Re-vendoring updates every field of that file in the same change.
  Check for a new release with `gh api repos/sparkle-project/Sparkle/releases/latest`, which excludes prereleases by definition.
  Never use `gh api repos/sparkle-project/Sparkle/releases --jq '.[0]'` — it returns the newest release of any kind and would vendor a beta into a signed app.
  An empty `latest` response means the check failed, not that the pin is current.
  dockishOS `_docs/05-infrastructure.md` owns the full re-vendor procedure; follow it rather than duplicating it here.
- Every Sparkle UI entry point must foreground this accessory app; keep the `AppPresentation.promoteToForeground()` + `startFloatingWindows()` pairing on all three entry points in `MovingPaperUpdater` — including `standardUserDriverWillShowModalAlert()` — and the `returnToAccessory()` restore on session finish.
- `_docs/todos.md` is the only active backlog; root `todos.md` is a tracked redirect stub — do not repopulate or delete it.
  Completed analysis belongs in `_docs/00-foundation.md` or git history.
