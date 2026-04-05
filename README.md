<p align="center">
  <img src="brand/moving-paper.png" alt="Moving Paper" width="200">
</p>

<h1 align="center">Moving Paper</h1>

<p align="center">
  A moving (wall)paper for your desktop.
</p>

<p align="center">
  <!-- version-badge -->v0.002<!-- /version-badge --> · macOS 15+ · Swift 6 · MIT
</p>

---

## The Story

I just wanted a simple way to animate my wallpaper while I code. No bloated app, no subscription, no electron wrapper -- just a native macOS menu bar utility that plays a video or GIF behind my desktop icons. That's it. That's the whole project.

The name is literal: it's your wallpaper, but it moves. Moving (Wall) Paper. **Moving Paper**.

---

## Download

<!-- download-link -->
[**Download Moving Paper v0.002**](https://github.com/8bittts/moving-paper/releases/download/v0.002/MovingPaper-0.002.dmg)
<!-- /download-link -->

Open the `.dmg`, drag **Moving Paper** to Applications, launch it. Look for the night sky icon in your menu bar -- that's it.

> Code-signed and notarized. If macOS warns you, right-click the app and choose "Open".

---

## What It Does

Plays a looping video or GIF as your desktop background. Icons, right-click menus, drag-and-drop all work normally -- the animation sits underneath.

| Format | Extensions | Notes |
|--------|-----------|-------|
| Video  | `.mp4`, `.mov`, `.m4v` | Seamless looping, HEVC with alpha |
| GIF    | `.gif` | Native frame timing |

## Features

- **Per-desktop wallpapers** -- different wallpaper on each macOS Space and monitor, like native macOS
- **Sound control** -- mute or unmute video audio (muted by default)
- **Multi-monitor** -- auto-detects displays, rebuilds on hot-plug
- **Power-aware** -- pauses on Low Power Mode and thermal throttling
- **Auto-updates** -- built-in Sparkle updater
- **Menu bar only** -- no Dock icon, no clutter

## Menu

| Item | |
|------|---|
| **Choose File...** | Pick a `.gif`, `.mp4`, `.mov`, or `.m4v` |
| **Sound: Off / On** | Toggle video audio |
| **Wallpaper Mode** | All Desktops or Per Desktop |
| **Pause / Resume** | Stop or restart playback |
| **Remove Wallpaper** | Clear wallpaper |
| **Check for Updates...** | Sparkle update check |
| **Quit Moving Paper** | Exit |

In **Per Desktop** mode, each Space and monitor gets its own wallpaper -- switch Spaces and the wallpaper changes with it.

---

## Build from Source

Requires macOS 15.0+ and Swift 6.0+.

```bash
git clone https://github.com/8bittts/moving-paper.git
cd moving-paper
swift build
swift run MovingPaper
```

```bash
swift test                         # 20 tests
./scripts/build-dmg.sh             # build + sign + DMG + notarize
./scripts/build-dmg.sh --local     # skip notarization
```

Version auto-increments on each build (`0.001` -> `0.002` -> ...).

---

## How It Works

A borderless `NSPanel` at `desktopWindow + 1` sits above the system wallpaper but below Finder icons. `ignoresMouseEvents = true` keeps the desktop interactive. Video loops via `AVQueuePlayer` + `AVPlayerLooper`. GIFs animate via `CGAnimateImageAtURLWithBlock`. Space changes are tracked via `CGSGetActiveSpace` + `activeSpaceDidChangeNotification` to swap per-desktop wallpapers.

## Tech Stack

| | |
|---|---|
| Build | Swift Package Manager |
| Windowing | AppKit (`NSPanel`, `NSStatusItem`) |
| UI | SwiftUI via `NSHostingView` |
| Video | AVFoundation (`AVQueuePlayer`, `AVPlayerLooper`) |
| GIF | ImageIO (`CGAnimateImageAtURLWithBlock`) |
| Desktop tracking | CoreGraphics (`CGSGetActiveSpace`) |
| Updates | [Sparkle](https://sparkle-project.org) (EdDSA, vendored) |

## Contributing

Fork, branch, `swift test`, PR. One feature or fix per PR.

## License

[MIT](LICENSE)
