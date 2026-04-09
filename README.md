<p align="center">
  <img src="build/movingpaper.png" alt="MovingPaper" width="200">
</p>

<h1 align="center">MovingPaper</h1>

<p align="center">
  A moving (wall)paper for your desktop.
</p>

<p align="center">
  <!-- version-badge -->v0.023<!-- /version-badge --> · macOS 15+ · Swift 6 · MIT
</p>

---

## Why MovingPaper?

Your desktop is yours. Why should it be a static photo?

MovingPaper turns your background into something alive, like a looping video, an animated GIF, a YouTube clip, or a random video from your Apple Photos library. Everything else works exactly the same: Icons, right-click menus, drag-and-drop, all of it. Your Moving (Wall) Paper animation sits underneath. I call it *MovingPaper*.

**A few ways people use it:**

- **Podcast background** -- listening to a podcast while you work? Set a chill looping video and let the visual ambiance match the vibe. Your desktop becomes the world's most relaxed studio.
- **Music visualizer** -- throw on a music video from YouTube as your wallpaper and code to the rhythm. It's like having MTV in the background, except it's 2026 and your wallpaper is the screen.
- **Photos shuffle** -- hit Shuffle and MovingPaper pulls a random video from your entire Apple Photos library. Family clips, travel memories, skateboard fails -- your desktop is never the same twice.
- **Aesthetic workspace** -- pixel art rain, fireplace loops, Japanese lo-fi scenes, slow-motion nature. Pick something beautiful and let it run.
- **Multiple desktops** -- set a different vibe on each macOS Space. Work desktop gets the calm ocean. Personal desktop gets the anime loop. You do you.

It's the kind of app that makes you smile every time you minimize a window.

---

## Download

<!-- download-link -->
[**Download MovingPaper v0.023**](https://github.com/8bittts/movingpaper/releases/download/v0.023/MovingPaper-0.023.dmg)
<!-- /download-link -->

Open the `.dmg`, drag **MovingPaper** to Applications, launch it. Look for the night sky icon in your menu bar -- that's it.

> Code-signed with Developer ID and notarized by Apple. Auto-updates via Sparkle.

---

## What It Does

Plays a looping video or GIF as your desktop background. Everything on your desktop still works normally -- the animation sits underneath.

| Source | How |
|--------|-----|
| **Video files** | `.mp4`, `.mov`, `.m4v` -- seamless looping, HEVC with alpha |
| **GIFs** | `.gif` -- native frame timing |
| **YouTube** | Paste any URL -- downloads and loops as wallpaper |
| **Apple Photos** | Pick a video or shuffle a random one from your library |

## Features

- **Apple Photos integration** -- pick a video or shuffle a random one from your entire library
- **YouTube wallpapers** -- paste a URL, it downloads and loops
- **Resilient async loading** -- stale YouTube and Photos results are cancelled or ignored so your newest wallpaper choice wins
- **Loading overlay** -- on-brand shimmer pill floats above all windows so you always know what's happening
- **Per-desktop wallpapers** -- different wallpaper on each macOS Space and monitor, including separate Spaces per display
- **Sound control** -- mute or unmute video audio (muted by default)
- **Multi-monitor** -- auto-detects displays, adapts on hot-plug
- **Power-aware** -- pauses on Low Power Mode and thermal throttling
- **Auto-updates** -- checks hourly via Sparkle; no-update alerts stay dockless, and real update sessions temporarily surface the app so Sparkle can present install UI correctly
- **Persistent** -- your wallpapers come back when you relaunch
- **Menu bar only** -- no Dock icon during normal use; Sparkle only surfaces the app temporarily while an update session is active

## Menu

| Item | |
|------|---|
| **Choose File...** | Pick a `.gif`, `.mp4`, `.mov`, or `.m4v` |
| **Paste YouTube URL...** | Download a YouTube video as wallpaper |
| **Choose from Photos...** | Pick a video from your Photos library |
| **Shuffle from Photos** | Random video from your entire library |
| **Sound: Off / On** | Toggle video audio |
| **MovingPaper Mode** | All Desktops or Per Desktop |
| **Pause / Resume** | Stop or restart playback |
| **Remove MovingPaper** | Clear wallpaper |
| **Check for Updates...** | Sparkle update check; if an update is available, MovingPaper temporarily surfaces so Sparkle's install window can be focused |
| **Built with YEN** | Visit yen.chat |
| **Quit MovingPaper** | Exit |

In **Per Desktop** mode, each Space and monitor gets its own wallpaper -- switch Spaces and the wallpaper changes with it, even when macOS is keeping separate active Spaces on different displays.

---

## Build from Source

Requires macOS 15.0+ and Swift 6.0+.

```bash
git clone https://github.com/8bittts/movingpaper.git
cd movingpaper
swift test
./script/build_and_run.sh
```

```bash
./script/build_and_run.sh --logs        # launch and stream app logs
./scripts/build-dmg.sh --build-only     # assemble release app bundle only
./scripts/build-dmg.sh --local          # build + sign + DMG, skip notarization
./scripts/build-dmg.sh --unsigned       # ad-hoc sign, no Developer ID
./scripts/release-movingpaper.sh        # bump + package + notarize + tag + GitHub release
```

Use `./script/build_and_run.sh` for local iteration so MovingPaper launches as a real `.app` bundle with Sparkle metadata and embedded frameworks. `swift run MovingPaper` is still fine for general app codepaths, but Sparkle stays dormant there because it is not a fully staged app bundle. `./scripts/build-dmg.sh` is now packaging-only, and `./scripts/release-movingpaper.sh` owns the version bump (`0.001` -> `0.002` -> ...) plus tag, README, and GitHub Release updates after the artifact build succeeds.

---

## How It Works

A borderless `NSPanel` at `desktopWindow + 1` sits above the system wallpaper but below Finder icons. `ignoresMouseEvents = true` keeps the desktop interactive. Video loops via `AVQueuePlayer` + `AVPlayerLooper`. GIFs animate via `CGAnimateImageAtURLWithBlock`. Per-display Space changes are tracked from macOS's managed display-space snapshot, with a `CGSGetActiveSpace` fallback, so wallpaper swaps stay aligned with the correct monitor and desktop without visible flash.

## Tech Stack

| | |
|---|---|
| Build | Swift Package Manager |
| Windowing | AppKit (`NSPanel`, `NSStatusItem`) |
| UI | SwiftUI via `NSHostingView` |
| Video | AVFoundation (`AVQueuePlayer`, `AVPlayerLooper`) |
| Photos | PhotosUI (`PHPickerViewController`) + PhotoKit (shuffle) |
| GIF | ImageIO (`CGAnimateImageAtURLWithBlock`) |
| Desktop tracking | CoreGraphics private APIs (`CGSCopyManagedDisplaySpaces`, `CGSGetActiveSpace`) |
| Updates | [Sparkle](https://sparkle-project.org) (EdDSA-signed appcast, vendored) |
| Signing | Developer ID + Apple notarization |

## Contributing

Fork, branch, `swift test`, PR. One feature or fix per PR.

## License

[MIT](LICENSE)

---

<p align="center">
  <img src="build/yen.png" alt="YEN Terminal" width="100%" />
</p>

<h3 align="center">Built with YEN</h3>

<p align="center">
  <a href="https://yen.chat">YEN</a> is a personal terminal experience that makes command-line work beautiful.<br/>
  Fast, customizable, and designed for developers who live in the terminal.<br/>
  <br/>
  <a href="https://yen.chat"><img src="https://img.shields.io/badge/Download-YEN-ff5100?style=for-the-badge" alt="Download YEN" /></a>
</p>
