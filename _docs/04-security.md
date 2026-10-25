# Security

Code signing, update-feed trust, the yt-dlp supply chain, permissions and the sandbox posture of MovingPaper.

## Sandbox and permissions

`MovingPaper.entitlements` sets `com.apple.security.app-sandbox` to false: the app reads private CoreGraphics Spaces state and runs yt-dlp as a subprocess, neither of which a sandboxed app can do.
Photos access is requested only when the user picks or shuffles from the library; the picker route uses `PHPickerViewController` and Shuffle uses PhotoKit authorization.
Wallpaper actions, Photos prompts and downloads are real side effects on the operator's desktop, so verification prefers source inspection and non-launching checks ([09-quality.md](09-quality.md)).

## Signing and notarization

Release builds are signed with a Developer ID certificate and notarized through `scripts/build-dmg.sh`; `--local` skips notarization and `--unsigned` signs ad hoc for bootstrapping.
`./scripts/smoke-test.sh --production` verifies the signature, the stapled notarization ticket, the DMG checksum and the signed appcast before a release.

## Update feed

Sparkle checks hourly against an EdDSA-signed feed with signed-feed enforcement and verify-before-extraction enabled in staged builds.
The vendored framework is pinned in `tools/sparkle/VERSION` (version, build, binary SHA-256, required paths) and `scripts/build-dmg.sh` refuses to build when the framework drifts from the pin; re-vendoring is the procedure dockishOS owns ([05-infrastructure.md](05-infrastructure.md)).
Every Sparkle UI entry point foregrounds the accessory app and returns it to accessory on finish, so update dialogs never appear behind other windows.

## yt-dlp supply chain

`YTDLPInstaller` pins yt-dlp by release version and SHA-256, bumped together.
The downloaded binary is hashed before it is installed and made executable, an installed copy is re-verified against the pin before every use, and a corrupt or pin-stale copy is re-downloaded rather than executed.
A dev-tree binary is trusted as-is for development only.
Downloads run serialized through `AsyncSerialGate`, and cancellation tears down the subprocess through `withTaskCancellationHandler`.

## Local data

Cached media and persisted wallpaper choices live under the app's own cache and support directories (`AppPaths`); `CacheJanitor` evicts media only where a recovery story exists.
The app collects no analytics and sends nothing but the Sparkle feed request and the media it is asked to fetch.
