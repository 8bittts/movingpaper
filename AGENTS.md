# MovingPaper agent notes

## Orientation

SwiftPM macOS menu-bar app (`sources/`, `tests/`).
Validate with `swift test` and `./scripts/smoke-test.sh`; `--production` also verifies signing, notarization, checksum, and the signed appcast without launching the wallpaper app.
See README "Build from Source" for the full script matrix; CI (`.github/workflows/ci.yml`) runs only `swift build` + `swift test`.
Owner-doc index: [_docs/00-docs-map.md](_docs/00-docs-map.md).

Sparkle work must go through `./scripts/build_and_run.sh`, which stages a real `.app` under `build/local-run/`.
`swift run MovingPaper` leaves Sparkle dormant.

Treat wallpaper runtime actions as real side effects.
Prefer source inspection and non-launching smoke checks over clicking menu actions that mutate the desktop wallpaper, request Photos access, or start downloads.

## Constraints

- Keep the production bundle identifier `com.8bittts.movingpaper` and preserve `AppIdentityDefaultsMigration` when touching defaults or bundle metadata.
- Do not reintroduce a visible Settings surface.
  `MovingPaperApp` keeps a hidden `Settings { EmptyView() }` scene for lifecycle only; the menu must not advertise Settings until a real preferences UI exists.
- `WallpaperManager` stays the coordinator; extracted helpers each own one seam (routing, persistence, presentation, cache cleanup, power state, request cancellation).
  Do not route wallpaper rendering back through SwiftUI — `WallpaperWindowRouter` hosts video/GIF directly in AppKit.
- A `WallpaperPersistenceStore` schema change is not done until a test covers the new migration path.
- New async wallpaper sources go through `WallpaperRequestCoordinator` so the newest user choice wins, and long-running subprocess or network work must cooperate with `withTaskCancellationHandler` so cancellation actually tears it down.
- Do not enroll a cache in `CacheJanitor` without a recovery story for an evicted file.
- `YouTubeDownloader` pins yt-dlp by version and hash — bump `pinnedYTDLPVersion` and `pinnedYTDLPSHA256` together.
- Every Sparkle UI entry point must foreground this accessory app; keep the `AppPresentation.promoteToForeground()` + `startFloatingWindows()` pairing on all three entry points in `MovingPaperUpdater` — including `standardUserDriverWillShowModalAlert()` — and the `returnToAccessory()` restore on session finish.
- `_docs/todos.md` is the only active backlog; root `todos.md` is a tracked redirect stub — do not repopulate or delete it.
  Completed analysis belongs in `_docs/audit-closure-2026.md` or git history.
