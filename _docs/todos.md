# MovingPaper TODOs

---

## MUST FOLLOW RULES and PROTOCOLS:

1. Never remove, delete, or modify this list unless directed to do so.
2. Active work only. Completed work lives in git history.
3. `_docs/todos.md` is the only backlog file.
4. Keep clear separation of concerns with phase-based checklists and zero task duplication.
5. Validate, review, and test each phase before moving to the next phase.
6. Stage and commit only files touched for the active phase. Ignore unrelated edits from other agents.
7. Write durable findings into the `_docs/` file that owns the topic, replacing any sentence they contradict; history and research go only in `00-foundation.md`.
8. End every phase with a docs-alignment step that updates internal and public documentation and runs the project's declared gates.
9. Root `todos.md` is a tracked redirect stub; never repopulate or delete it.

---

## Active Work

- [ ] **#50 Homebrew Cask lag** — `Casks/movingpaper.rb` is pinned to 0.040 while the current release is 0.043. No release script bumps it. Either add the bump to `scripts/release-movingpaper.sh` or bump the Cask by hand each release.
- [ ] **#29 runtime sanity check** — With a fullscreen app covering the wallpaper, confirm `WallpaperWindowController` pauses `AVQueuePlayer` on occlusion and resumes when visible again. Low-risk; revertable if wrong.

Deferred Apple HIG follow-ups (not this pass):

- **#44 Dock fallback** — HIG says do not rely on extras; this app is dockless by design (`LSUIElement`, `AGENTS.md`). Revisit only if we add an explicit “Show Dock Icon” command.
- **#45 Icon Composer app icon** — Flattened pre-rounded `.icns`. Needs Icon Composer layers and appearance variants.
- **#46 first-run discoverability** — Silent launch. HIG also says do not alert on startup. Needs a non-alert one-time hint, not a launch sheet.
- **#47 system-material HUD** — Night-sky overlay is brand. Do not restyle it as Liquid Glass in this pass.
- **#48 String Catalog** — All copy is English. Localize in a dedicated pass.
