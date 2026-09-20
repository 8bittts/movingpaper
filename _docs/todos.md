# MovingPaper TODOs

---
## MUST FOLLOW RULES and PROTOCOLS:
1. Never remove, delete, or modify this list unless directed to do so.
2. Active work only. Completed work lives in git history.
3. This is the ONLY TODO/backlog file.

---

## Active Work

- [ ] **#49 Swift 6.4 default build system** — `Package.swift` passes a relative `-F tools/sparkle` through `unsafeFlags`. The 6.4 default `swiftbuild` system sets `-working-directory` to the package's parent, so Sparkle no longer resolves and `swift build` / `swift test` both fail. `--build-system native` is the current workaround and passes 133 tests. Fix the search path (or move Sparkle to a binary target), then drop the workaround from `README.md`, `AGENTS.md`, `scripts/build-dmg.sh`, `scripts/build_and_run.sh`, `scripts/smoke-test.sh`, and `.github/workflows/ci.yml`.
- [ ] **#50 Homebrew Cask lag** — `Casks/movingpaper.rb` is pinned to 0.040 while the current release is 0.043. No release script bumps it. Either add the bump to `scripts/release-movingpaper.sh` or bump the Cask by hand each release.
- [ ] **#29 runtime sanity check** — With a fullscreen app covering the wallpaper, confirm `WallpaperWindowController` pauses `AVQueuePlayer` on occlusion and resumes when visible again. Low-risk; revertable if wrong.

Deferred Apple HIG follow-ups (not this pass):

- **#44 Dock fallback** — HIG says do not rely on extras; this app is dockless by design (`LSUIElement`, `AGENTS.md`). Revisit only if we add an explicit “Show Dock Icon” command.
- **#45 Icon Composer app icon** — Flattened pre-rounded `.icns`. Needs Icon Composer layers and appearance variants.
- **#46 first-run discoverability** — Silent launch. HIG also says do not alert on startup. Needs a non-alert one-time hint, not a launch sheet.
- **#47 system-material HUD** — Night-sky overlay is brand. Do not restyle it as Liquid Glass in this pass.
- **#48 String Catalog** — All copy is English. Localize in a dedicated pass.

Historical audit closure (34 shipped fixes, won't-fix registry): [`audit-closure-2026.md`](./audit-closure-2026.md).
HIG menu-bar extra pass (#30–#43) is in git history.
