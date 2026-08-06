# movingpaper Documentation Map

Quick index of documentation surfaces. Product: macOS menu-bar live wallpaper app. Agent routing: `AGENTS.md`.

There is no numbered `_docs/` series — **`README.md` is the primary doc surface.**

---

## Documentation surfaces

| Doc | Owns |
|-----|------|
| `README.md` | User features, build, release, smoke-test matrix, permissions |
| `AGENTS.md` | Agent constraints (no Settings UI, WallpaperManager seams, yt-dlp pin, Sparkle hooks) |
| `todos.md` | **Only** active backlog (#29 runtime check) |
| `audit-closure-2026.md` | Shipped audit fixes + won't-fix registry (2026) |

## Sibling macOS apps

| Project | Release doc home |
|---------|------------------|
| dockishOS | `BUILD.md` + [`../dockishOS/_docs/00-docs-map.md`](../dockishOS/_docs/00-docs-map.md) |
| movingpaper | `README.md` (embedded build/release) |

## Known doc drift (audit 2026-08-06)

- No separate `BUILD.md` (unlike dockishOS) — acceptable at this scale.
