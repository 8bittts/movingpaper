# MovingPaper Documentation Map

macOS menu-bar app that plays a looping video, GIF, YouTube clip or Photos video as the desktop wallpaper.
Agent routing lives in `AGENTS.md`; this index follows the fleet documentation standard that `/docs` audits against.

## Owner docs

| Doc                    | Owns                                                                                                  |
| ---------------------- | ----------------------------------------------------------------------------------------------------- |
| `00-foundation.md`     | History, decisions and the audit closure record                                                       |
| `01-architecture.md`   | Stack, wallpaper panel, coordinator seams, sources, status item, modes, build pipeline                 |
| `02-design-system.md`  | Marks, the template status-item symbol, overlay style, menu copy                                       |
| `04-security.md`       | Sandbox and permissions, signing and notarization, update-feed trust, yt-dlp supply chain, local data |
| `05-infrastructure.md` | Scripts, release, distribution, Sparkle vendoring, CI, toolchain                                       |
| `09-quality.md`        | Gates, test strategy, static analysis, manual verification                                            |
| `todos.md`             | The only backlog; active work only                                                                    |

## Not applicable

- `03-data.md`: the only persisted data is the wallpaper store, owned by `01-architecture.md`.
- `06-payments.md`, `07-email.md`, `08-growth.md`, `10-gtm.md`: the app is free, sends nothing, and has no analytics or marketing surface.

## Other surfaces

| Path                         | Notes                                                                                                 |
| ---------------------------- | ----------------------------------------------------------------------------------------------------- |
| `AGENTS.md`                  | Orientation and the constraints that bind every change                                                |
| `README.md`                  | User-facing features, download, Homebrew, menu, quick build; points here                              |
| `todos.md` (root)            | Tracked redirect stub to `_docs/todos.md`; never repopulate or delete it                              |
| `Casks/movingpaper.rb`       | Homebrew Cask, bumped by hand after a release                                                         |
| `tools/sparkle/VERSION`      | Sparkle vendoring pin read by the build preflight                                                     |
| `.periphery.yml`             | Periphery configuration                                                                               |
| `.github/workflows/ci.yml`   | CI: build and test only                                                                               |
| `videos/`                    | Sample wallpapers                                                                                     |

## Sibling macOS apps

dockishOS shares the Sparkle pipeline and owns the re-vendor procedure in [`../../dockishOS/_docs/05-infrastructure.md`](../../dockishOS/_docs/05-infrastructure.md); its index is [`../../dockishOS/_docs/00-docs-map.md`](../../dockishOS/_docs/00-docs-map.md).

## Authority order

Code, scripts and tests, then the owner doc, then `AGENTS.md`, then `README.md`.

## Known doc drift

None.
