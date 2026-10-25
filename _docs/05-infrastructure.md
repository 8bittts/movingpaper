# Infrastructure

Build scripts, release pipeline, distribution channels, Sparkle vendoring and CI for MovingPaper.

## Scripts

| Command                                 | Behavior                                                                                      |
| --------------------------------------- | --------------------------------------------------------------------------------------------- |
| `./scripts/build_and_run.sh`            | Stage a real `.app` under `build/local-run/` and launch it; the only path where Sparkle is live |
| `./scripts/build_and_run.sh --logs`     | Launch and stream the app's unified logs                                                      |
| `./scripts/smoke-test.sh`               | Tests, release build, staged bundle and bundle-shape checks without launching the wallpaper   |
| `./scripts/smoke-test.sh --production`  | Also require and verify the signed app, notarized DMG, checksum and signed appcast            |
| `./scripts/build-dmg.sh --build-only`   | Assemble the release app bundle only                                                          |
| `./scripts/build-dmg.sh --local`        | Build, sign and package the DMG, skipping notarization                                        |
| `./scripts/build-dmg.sh --unsigned`     | Ad-hoc sign without a Developer ID                                                            |
| `./scripts/build-dmg.sh`                | Signed and notarized release DMG                                                              |
| `./scripts/release-movingpaper.sh`      | Bump the version, package, notarize, tag and publish the GitHub release                       |
| `./scripts/generate-appcast.sh`         | Regenerate and re-sign the Sparkle appcast                                                    |

`scripts/lib/plist.sh` holds the shared plist helpers, and `scripts/generate-app-icon.swift` and `scripts/generate-banner.swift` produce the brand assets ([02-design-system.md](02-design-system.md)).
`swift run MovingPaper` is fine for general code paths, but Sparkle stays dormant there.

## Release

The release script bumps the version, builds and notarizes the DMG, tags the release and publishes it on GitHub Releases, and it updates the README's `<!-- version-badge -->` and `<!-- download-link -->` markers.
It does not touch `Casks/movingpaper.rb`, so the Homebrew Cask is bumped by hand after a release and can lag the latest DMG; Sparkle auto-update keeps installed apps current between Cask bumps.
Run `./scripts/smoke-test.sh --production` before shipping; in default mode an existing `build/MovingPaper.app` also triggers the release-artifact check, so a stale bundle without its DMG fails until `./scripts/build-dmg.sh` rebuilds it.
Notarization uses the keychain profile `YEN-Notarization` unless `MOVINGPAPER_NOTARY_PROFILE` names another; the build writes `SUFeedURL`, `SURequireSignedFeed` and `SUVerifyUpdateBeforeExtraction` into the bundle's plist through `scripts/lib/plist.sh`.

## Distribution

- Direct download: the DMG attached to each GitHub release, Apple Silicon only, signed and notarized.
- Homebrew: the repository doubles as a tap; `brew install --cask` works from the raw Cask URL or after `brew tap 8bittts/movingpaper`.
- In-app: Sparkle checks hourly from the EdDSA-signed feed.

## Sparkle vendoring

The vendored framework lives at `tools/sparkle/Sparkle.framework` and is pinned in `tools/sparkle/VERSION` to version 2.10.0, build 2064, with the main binary's SHA-256 and the required helper paths.
The `scripts/build-dmg.sh` preflight fails the build when the framework drifts from the pin, and re-vendoring updates every field of that file in the same change.
Check for a new release with `gh api repos/sparkle-project/Sparkle/releases/latest`, never the newest entry of `releases`, which can be a beta; an empty `latest` response means the check failed.
The full re-vendor procedure is owned by dockishOS in [`../../dockishOS/_docs/05-infrastructure.md`](../../dockishOS/_docs/05-infrastructure.md); follow it rather than a local copy.

## CI

`.github/workflows/ci.yml` runs on every push and pull request to `main` on `macos-15`: `swift build` and `swift test --parallel` with a SwiftPM cache.
Signing, notarization, Periphery and the smoke matrix run locally only.

## Toolchain

`Package.swift` anchors the Sparkle search and rpath flags to the manifest so they resolve under Swift 6.4's default `swiftbuild` system and under `--build-system native`.
Periphery 3.8.0 finds no index store under `swiftbuild`, so `.periphery.yml` passes `--build-system native` ([09-quality.md](09-quality.md)).
