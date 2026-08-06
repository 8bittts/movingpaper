# MovingPaper — Audit closure record (2026)

Historical source audit of `sources/` (~3,081 LOC). **Not the active backlog** — see [`todos.md`](./todos.md) for open work.

**Status: 34 findings fixed, suite grown 79 → 101 tests.** Every change gated on `swift build` + `swift test`.

---

## Done (shipped to `main`)

**Correctness / data-loss**
- #3 — pending YouTube redownloads re-persisted on every save (was permanent data loss on cache eviction).
- #1 — restore-redownload batch no longer aborted by unrelated local/Photos/clear actions.
- #11/#28 — downloads serialized via `AsyncSerialGate` (FIFO async mutex).
- #2/#8 — `download` returns a per-call `DownloadOutcome`.
- #7 — a "for all" pick in perDesktop mode now applies to every display.
- #9 — mode-collapse / reconcile pick a deterministic `canonicalEntry`.
- #14/#43 — Photos picker never returns a cache path when the file copy failed.

**Concurrency, security, robustness** — see git history (`177df9d..90a6358`) for #26, #4/#27, #13, #12, #41, #10/#44, #23, #15/#34, #42.

---

## Open runtime check

- **#29** — `WallpaperWindowController` occlusion pause/resume. **Needs a runtime sanity check** (fullscreen app → wallpaper pauses → resumes on return).

---

## Closed as won't-fix

- **#19/#21** `AppPresentation` refcount — incompatible with Sparkle lifecycle in `AGENTS.md`.
- **#23** (ordering half) — moot at launch-time eviction.
- **#22** hidden Settings scene — sanctioned in `AGENTS.md`.
- **#20** menu builder extract — already decomposed sufficiently.
- **#16**, **#30**, **#31** — see original audit rationale in git history.
