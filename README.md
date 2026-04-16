<p align="center">
  <img src="build/movingpaper.png" alt="MovingPaper" width="200">
</p>

<h1 align="center">MovingPaper</h1>

<p align="center">
  A moving (wall)paper for your desktop.
</p>

<p align="center">
  <!-- version-badge -->v0.032<!-- /version-badge --> · macOS 15+ · Swift 6 · MIT · <a href="https://x.com/8BIT/status/2043384259482902603">Short Demo</a>
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
[**Download MovingPaper v0.032**](https://github.com/8bittts/movingpaper/releases/download/v0.032/MovingPaper-0.032.dmg)
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
| **YouTube** | Paste a YouTube URL -- downloads and loops as wallpaper |
| **Apple Photos** | Pick a video or shuffle a random one from your library |

## Features

- **Apple Photos integration** -- pick a video or shuffle a random one from your entire library
- **YouTube wallpapers** -- paste a supported YouTube URL, it downloads and loops
- **Resilient async loading** -- stale YouTube and Photos results are cancelled or ignored so your newest wallpaper choice wins
- **Loading overlay** -- on-brand shimmer pill floats above all windows so you always know what's happening
- **Per-desktop wallpapers** -- different wallpaper on each macOS Space and monitor, including separate Spaces per display
- **Sound control** -- mute or unmute video audio (muted by default)
- **Multi-monitor** -- auto-detects displays, adapts on hot-plug
- **Power-aware** -- pauses on Low Power Mode and thermal throttling
- **Automatic update checks** -- checks hourly via Sparkle using a custom app-owned updater dialog that stays dockless, with signed feeds and verify-before-extraction enabled in staged builds
- **Persistent** -- your wallpapers come back when you relaunch
- **Menu bar only** -- no Dock icon during normal use, update checks, or update install prompts

## Menu

| Item | |
|------|---|
| **Choose File...** | Pick a `.gif`, `.mp4`, `.mov`, or `.m4v` |
| **Paste YouTube URL...** | Download a supported YouTube URL as wallpaper |
| **Choose from Photos...** | Pick a video from your Photos library |
| **Shuffle from Photos** | Random video from your entire library |
| **Sound: Off / On** | Toggle video audio |
| **MovingPaper Mode** | All Desktops or Per Desktop |
| **Pause / Resume** | Stop or restart playback |
| **Remove MovingPaper** | Clear wallpaper |
| **Check for Updates...** | Sparkle update check in MovingPaper's custom dockless updater dialog |
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
./scripts/smoke-test.sh
./scripts/build_and_run.sh
```

```bash
./scripts/build_and_run.sh --logs       # launch and stream app logs
./scripts/smoke-test.sh --production    # verify tests, release build, signing, notarized DMG, checksum, appcast
./scripts/build-dmg.sh --build-only     # assemble release app bundle only
./scripts/build-dmg.sh --local          # build + sign + DMG, skip notarization
./scripts/build-dmg.sh --unsigned       # ad-hoc sign, no Developer ID
./scripts/release-movingpaper.sh        # bump + package + notarize + tag + GitHub release
```

Use `build_and_run.sh` for anything that touches Sparkle — it launches a fully staged `.app` bundle. `swift run MovingPaper` is fine for general codepaths, but Sparkle stays dormant there.

Use `smoke-test.sh` before shipping changes. The default mode does not launch the wallpaper app; it runs the test suite, builds release, assembles a staged app bundle, and verifies core bundle shape. `--production` also requires and verifies the signed release app, signed and notarized DMG, checksum, and signed Sparkle appcast metadata.

Don't have any videos or GIFs on-hand? The `build/tests/` folder ships with a few sample wallpapers you can load into MovingPaper to try it out. More will be added over time.

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
| Updates | [Sparkle](https://sparkle-project.org) 2.9.1 (EdDSA-signed feed, signed archives, signed-feed enforcement, verify-before-extraction, vendored) |
| Signing | Developer ID + Apple notarization |
| Static analysis | [Periphery](https://github.com/peripheryapp/periphery) (unused code detection) |

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
