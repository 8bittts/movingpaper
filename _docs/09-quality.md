# Quality

Gates, test strategy, static analysis and verification rules for MovingPaper.

## Gates

`swift test` runs the unit suite in `tests/`, and `./scripts/smoke-test.sh` is the pre-ship gate: it runs the tests, builds release, assembles a staged app bundle and verifies the bundle shape without launching the wallpaper.
`./scripts/smoke-test.sh --production` also requires and verifies the signed release app, the signed and notarized DMG, the checksum and the signed Sparkle appcast, and the release flow runs it as its production gate.
CI runs only `swift build` and `swift test --parallel` ([05-infrastructure.md](05-infrastructure.md)).

## Test strategy

Wallpaper runtime actions are real side effects: they mutate the desktop wallpaper, request Photos access and start downloads.
Prefer source inspection and non-launching checks over clicking menu actions.
The status-menu structure lives in `MenuSnapshot`, so tests cover menu labels without launching the app.
A `WallpaperPersistenceStore` schema change is not done until a test covers the new migration path.
Mutation-test a new guard by breaking what it protects and watching it fail.

## Static analysis

Periphery 3.8.0 (`.periphery.yml`) finds unused code; install the final 3.8.0 binary from its GitHub release because upstream is archived and the Homebrew cask is stale.
It passes `--build-system native` because Swift 6.4's default build system writes no index store where Periphery looks, and it retains public, `@objc`, protocol-parameter and assign-only declarations on purpose.

## Manual verification

Use `./scripts/build_and_run.sh --logs` for anything that touches Sparkle, the loading overlay or per-display Space tracking, and confirm the behavior on more than one display when a change touches Spaces.
Open items that still need a runtime check live in `todos.md`.
