# MovingPaper — Audit TODOs

Full source audit of `sources/` (~3,081 LOC). 53 findings verified adversarially against real source; 4 duplicates merged → 49. This file tracks what shipped and what's left.

**Status: 30 findings fixed, suite grown 79 → 100 tests, 15 commits on `main` (`177df9d..4feb362`).** Every change gated on `swift build` + `swift test`.

---

## Done (shipped to `main`)

**Correctness / data-loss**
- #3 — pending YouTube redownloads re-persisted on every save (was permanent data loss on cache eviction).
- #1 — restore-redownload batch no longer aborted by unrelated local/Photos/clear actions.
- #11/#28 — downloads serialized via `AsyncSerialGate` (FIFO async mutex); concurrent per-display requests no longer clobber each other's subprocess.
- #2/#8 — `download` returns a per-call `DownloadOutcome`; failures reported from the actual call, not race-prone shared state.
- #7 — a "for all" pick that resolves in perDesktop mode now applies to every display instead of vanishing.
- #9 — mode-collapse / reconcile pick a deterministic `canonicalEntry`, not arbitrary dict order.
- #14/#43 — Photos picker never returns a cache path when the file copy failed.

**Concurrency**
- #26 / #3-video — video resume observes the queue player on the main thread (not the never-ready looper template item).
- #4/#27 — GIF animation guarded by a lock-protected generation token (off-thread read + double-loop leak).
- #13 — yt-dlp install hash + write run off the main actor (`nonisolated`).

**Security / robustness**
- #12 — yt-dlp install writes `.atomic` (no truncated, permanently-trusted binary).
- #41 — yt-dlp stderr drained incrementally (pipe-fill deadlock).
- #10/#44 — partial-download cleanup targets the real `<videoID>.mp4.part`.
- #23 (protection half) — `CacheJanitor` never evicts a file a live wallpaper references.

**Refactor / dead code / perf**
- #4/#37 — dropped unused `ObservableObject`/`@Published` on `WallpaperManager`.
- #8/#35 — deleted dead `AllDesktopAssignmentReconciler` (+ test).
- #6/#38 — deduped `connectedDisplayIDs` helper. #5/#40 — fixed stale doc comment.
- #36 — Space presence is an explicit `String?`, not a `"No MovingPaper"` sentinel across two files.
- #39 — deduped the two Photos-picker handlers.
- #18 — `Check for Updates` menu gate honored (`autoenablesItems = false`).
- #32 — skip the no-op window reframe. #33 — precompiled progress regex.

**Test coverage added**
- #46/#47 persistence load branches, #50 cache-janitor boundary + multi-file, #48/#49 request-coordinator cancel/completion, #51 display-spaces snapshot edges, #52 router reconcile branch matrix, plus `AsyncSerialGate` serialization/FIFO/cancel tests.

**Ruled out (not a bug):** #17 — `PHAccessLevel` has no `.readOnly`; `.readWrite` is the minimal readable level.

---

## Remaining — blocked (needs the running app, a product call, or an untestable path)

Each was inspected; none is safe to do blind in a headless session against a signed, auto-updating release.

- **#42** re-verify cached yt-dlp SHA before exec — 40 MB re-hash per use for marginal local-attacker benefit; download path untestable here, and #12's atomic write already closes the self-corruption vector.
- **#19/#21** `AppPresentation` foreground/accessory refcount — pairing is ad-hoc across ~7 sites; refcounting risks a stuck dock icon / lost focus mid-picker. Needs the real app to verify.
- **#29** pause playback when the desktop is fully occluded — feature; needs `NSWindow` occlusion + runtime verification.
- **#23** (ordering half) evict by use-time, not download mtime — needs an access-time tracking design.
- **#22** hidden `Settings { EmptyView() }` scene exposes a blank Cmd+, window — product decision (CLAUDE.md currently sanctions the hidden scene).
- **#20** extract the 422-LOC `StatusBarController` menu builder — pure churn with no test coverage of the interactive menu to catch a wiring regression.
- **#15/#34** unbounded Photos-picker cache — CLAUDE.md forbids enrolling unrecoverable caches without a recovery story (PHPicker gives no persistent asset ref to redownload from).

_Dropped after inspection (the "fix" would regress or has no benefit): #16 (cancellation handlers already bound `withTimeout`), #30 (overlay resize is required for changing message width), #31 (menu-bar icon re-render is retina-correct)._
