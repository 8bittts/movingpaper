# Foundation

History, decisions and the audit closure record for MovingPaper; every other doc describes the code as it is.

## Timeline

Dates are the evidence in this doc; the owner docs carry none.

- 2026-04-04: the initial commit and the first releases, v0.002 through v0.008, ship in one day, including per-desktop wallpapers across Spaces and the brand icon in the menu bar.
- 2026-04-05: v0.009 through v0.018 add styled Sparkle release notes generated from git history, auto-tagging, Sparkle windows above all windows, and the fix for Photos shuffle hangs and the authorization prompt.
- 2026: a source audit of `sources/` (about 3,081 lines) fixes 34 findings and grows the suite from 79 to 101 tests; its record is below.
- 2026: the HIG menu-bar extra pass (#30 to #43) lands; its deferred follow-ups stay in `todos.md`.

## Decisions

- **Dockless by design.** The app is an accessory (`LSUIElement`) with no Dock icon during normal use, update checks or install prompts; the Dock-fallback HIG item is deferred unless an explicit Show Dock Icon command is added.
- **No visible Settings surface** until a real preferences UI exists; `AGENTS.md` carries the rule.
- **Exact pins for what the app downloads.** yt-dlp is pinned by version and SHA-256 and Sparkle by version, build and binary hash ([04-security.md](04-security.md)).
- **One doc set for the two macOS apps.** dockishOS owns the Sparkle re-vendor procedure and MovingPaper cites it; MovingPaper's own release path lives in [05-infrastructure.md](05-infrastructure.md) rather than in a root build document or the README.
- **The Homebrew Cask is bumped by hand.** The release script does not touch `Casks/movingpaper.rb`; closing that gap is tracked in `todos.md`.

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
