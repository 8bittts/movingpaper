# MovingPaper — Audit TODOs

Full source audit of `sources/` (~3,081 LOC). 53 findings verified adversarially against real source; 4 duplicates merged → 49. This file tracks what shipped and what's left.

**Status: 34 findings fixed, suite grown 79 → 101 tests, 18 commits on `main` (`177df9d..90a6358`).** Every change gated on `swift build` + `swift test`.

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

## Also fixed (round 7)

- **#15/#34** — `CacheJanitor.pruneUnreferencedPhotosCaches` deletes orphaned picker/shuffle cache files at launch. Only removes files no live wallpaper references (nothing to recover), so it respects the "don't evict unrecoverable caches" rule while bounding growth. New test.
- **#42** — `ensureYTDLP` now re-verifies an installed yt-dlp against the pinned SHA-256 before executing it, re-downloading if corrupt/tampered/pin-stale (also fixes the latent bug where a pin bump never triggered a re-download). Runs off the main actor; only on a cache miss.
- **#29** — `WallpaperWindowController` pauses its `AVQueuePlayer` when the panel is fully occluded (via `NSWindow.didChangeOcclusionStateNotification` / `occlusionState`) and resumes when visible. Observer reacts only to occlusion *changes*, so a fresh wallpaper can't be frozen by a false initial state. **Needs a runtime sanity check** (open a fullscreen app, confirm the wallpaper pauses then resumes on return); low-risk and revertable.

## Closed as won't-fix (inspected; fixing would regress, is moot, or violates a constraint)

- **#19/#21** `AppPresentation` refcount — **incompatible** with the Sparkle standard-driver lifecycle CLAUDE.md mandates: `checkForUpdates` + `WillShowModalAlert`/`WillHandleShowingUpdate` fire multiple `promoteToForeground()` balanced by a single `returnToAccessory()` in `WillFinishUpdateSession`; a counter would leave the app stuck in `.regular` (dock icon persists). The stateless idempotent toggle is the correct design for that flow.
- **#23** (ordering half) — moot: eviction runs only at launch with a launch-time referenced set, so session use-time can't affect it. The protection half (in-use files never evicted) is already shipped.
- **#22** hidden `Settings { EmptyView() }` scene — CLAUDE.md explicitly sanctions keeping it for lifecycle; removing/altering it is out of bounds and risks lifecycle breakage.
- **#20** extract the `StatusBarController` menu builder — already decomposed into `rebuildMenu`/`build*Menu`/`buildDisplaySubmenu` + action handlers; a separate builder only adds callback indirection (actions need `self` as target) with no coupling reduction, on a surface with no menu tests.
- **#16** (`withTimeout`) — the operations' cancellation handlers already bound wall-clock in practice; racing-without-await would leak the operation task.
- **#30** (overlay re-center) — the resize is required for changing message width. **#31** (menu-bar icon re-render) — the drawing-handler re-render is retina-correct; baking a bitmap would lose crispness.
