# MovingPaper agent notes

## Orientation

SwiftPM macOS menu-bar app (`sources/`, `tests/`).
Validate with `swift test` and `./scripts/smoke-test.sh`; `--production` also verifies signing, notarization, checksum, and the signed appcast without launching the wallpaper app.
See README "Build from Source" for the full script matrix; CI (`.github/workflows/ci.yml`) runs only `swift build` + `swift test`.
Owner-doc index: [_docs/00-docs-map.md](_docs/00-docs-map.md).

Sparkle work must go through `./scripts/build_and_run.sh`, which stages a real `.app` under `build/local-run/`.
`swift run MovingPaper` leaves Sparkle dormant, and repo-root `dist/` is not used.

Treat wallpaper runtime actions as real side effects.
Prefer source inspection and non-launching smoke checks over clicking menu actions that mutate the desktop wallpaper, request Photos access, or start downloads.

## Constraints

- Keep the production bundle identifier `com.8bittts.movingpaper` and preserve `AppIdentityDefaultsMigration` when touching defaults or bundle metadata.
- Do not reintroduce a visible Settings surface.
  `MovingPaperApp` keeps a hidden `Settings { EmptyView() }` scene for lifecycle only; the menu must not advertise Settings until a real preferences UI exists.
- `WallpaperManager` stays the coordinator; extracted helpers each own one seam (routing, persistence, presentation, cache cleanup, power state, request cancellation).
  Do not route wallpaper rendering back through SwiftUI — `WallpaperWindowRouter` hosts video/GIF directly in AppKit.
- Changing the on-disk shape in `WallpaperPersistenceStore` requires bumping `currentSchemaVersion`, adding a step to `runMigrationsIfNeeded`, and covering the new path with a test.
- New async wallpaper sources go through `WallpaperRequestCoordinator` so the newest user choice wins, and long-running subprocess or network work must cooperate with `withTaskCancellationHandler` so cancellation actually tears it down.
- Do not enroll a cache in `CacheJanitor` without a recovery story; the Photos picker and shuffle caches are excluded because an evicted file cannot be re-fetched (the source `PHAsset` is not persisted).
- `YouTubeDownloader` pins yt-dlp by version and hash — bump `pinnedYTDLPVersion` and `pinnedYTDLPSHA256` together.
- Every Sparkle UI entry point must foreground this accessory app: `checkForUpdates()`, `standardUserDriverWillShowModalAlert()`, and `standardUserDriverWillHandleShowingUpdate(...)` each call `AppPresentation.promoteToForeground()` + `startFloatingWindows()`.
  `standardUserDriverWillFinishUpdateSession()` restores accessory mode via `returnToAccessory()`.
  Missing the modal-alert hook makes the "up to date", error, and permission alerts surface unfocused or behind other windows.
- `_docs/todos.md` is the only backlog file and is active-work only; completed analysis belongs in `_docs/audit-closure-2026.md` or git history.
