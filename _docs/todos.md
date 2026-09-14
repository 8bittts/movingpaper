# MovingPaper TODOs

---
## MUST FOLLOW RULES and PROTOCOLS:
1. Never remove, delete, or modify this list unless directed to do so.
2. Active work only. Completed work lives in git history.
3. This is the ONLY TODO/backlog file.

---

## Active Work

- [ ] **#29 runtime sanity check** — With a fullscreen app covering the wallpaper, confirm `WallpaperWindowController` pauses `AVQueuePlayer` on occlusion and resumes when visible again. Low-risk; revertable if wrong.

Deferred Apple HIG follow-ups (not this pass):

- **#44 Dock fallback** — HIG says do not rely on extras; this app is dockless by design (`LSUIElement`, `AGENTS.md`). Revisit only if we add an explicit “Show Dock Icon” command.
- **#45 Icon Composer app icon** — Flattened pre-rounded `.icns`. Needs Icon Composer layers and appearance variants.
- **#46 first-run discoverability** — Silent launch. HIG also says do not alert on startup. Needs a non-alert one-time hint, not a launch sheet.
- **#47 system-material HUD** — Night-sky overlay is brand. Do not restyle it as Liquid Glass in this pass.
- **#48 String Catalog** — All copy is English. Localize in a dedicated pass.

Historical audit closure (34 shipped fixes, won't-fix registry): [`audit-closure-2026.md`](./audit-closure-2026.md).
HIG menu-bar extra pass (#30–#43) is in git history.
