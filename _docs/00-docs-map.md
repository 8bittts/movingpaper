# movingpaper Documentation Map

Quick index of documentation surfaces. Product: macOS menu-bar live wallpaper app. Agent routing: `AGENTS.md`.

There is no numbered `_docs/` series — **`README.md` is the primary doc surface.**

---

## Documentation surfaces

| Doc | Owns |
|-----|------|
| `README.md` | User features, build, release, smoke-test matrix, permissions |
| `AGENTS.md` | Agent constraints (no Settings UI, template extra icon, WallpaperManager seams, `YTDLPInstaller` pin, Sparkle hooks and vendor pin) |
| `_docs/todos.md` | **Only** active backlog (#29 runtime check; build + release #49–#50; deferred HIG #44–#48) |
| `_docs/audit-closure-2026.md` | Shipped audit fixes + won't-fix registry (2026) |
| Root `todos.md` | Stub redirect → `_docs/todos.md` |

## Sibling macOS apps

| Project | Release doc home |
|---------|------------------|
| dockishOS | `BUILD.md` + [`../../dockishOS/_docs/00-docs-map.md`](../../dockishOS/_docs/00-docs-map.md) |
| movingpaper | `README.md` (embedded build/release) |

## Settled doc decisions

- No separate `BUILD.md` (unlike dockishOS) — acceptable at this scale.
  `README.md` owns build and release; `AGENTS.md` owns the Sparkle vendor-pin rules and cites dockishOS `BUILD.md` for the full re-vendor procedure.
