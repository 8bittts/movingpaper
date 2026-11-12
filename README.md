<p align="center">
  <img src="build/movingpaper.png" alt="MovingPaper" width="200">
</p>

<h1 align="center">MovingPaper</h1>

<p align="center">
  A moving (wall)paper for your desktop.
</p>

<p align="center">
  <!-- version-badge -->v0.045<!-- /version-badge --> · macOS 27+ · Apple Silicon · Swift 6 · MIT · <a href="https://x.com/8BIT/status/2043384259482902603">Short Demo</a>
</p>

---

## Why MovingPaper?

Your desktop is yours.
Why should it be a static photo?

MovingPaper turns your background into something alive, like a looping video, an animated GIF, a YouTube clip, or a random video from your Apple Photos library.
Everything else works exactly the same: Icons, right-click menus, drag-and-drop, all of it.
Your Moving (Wall) Paper animation sits underneath.
I call it *MovingPaper*.

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
[**Download MovingPaper v0.045**](https://github.com/8bittts/movingpaper/releases/download/v0.045/MovingPaper-0.045.dmg)
<!-- /download-link -->

Open the `.dmg`, drag **MovingPaper** to Applications, launch it.
Look for the MovingPaper icon -- the night sky -- in your menu bar. That's it.

> Apple Silicon (arm64). Code-signed with Developer ID and notarized by Apple. Auto-updates via Sparkle.
>
> MovingPaper requires macOS 27 from the release after v0.044. v0.044 is the last release for macOS 15 through 26, and Sparkle does not offer a newer one to those Macs.

### Homebrew

The repo doubles as a Homebrew tap, so you can install via [Homebrew Cask](https://docs.brew.sh/Cask-Cookbook) without leaving the terminal:

```bash
# One-shot install of the latest release (no tap):
brew install --cask https://raw.githubusercontent.com/8bittts/movingpaper/main/Casks/movingpaper.rb

# Or tap the repo for ongoing `brew upgrade` updates:
brew tap 8bittts/movingpaper https://github.com/8bittts/movingpaper
brew install --cask 8bittts/movingpaper/movingpaper
```

The Cask formula in [`Casks/movingpaper.rb`](Casks/movingpaper.rb) is pinned to the current release by `release-movingpaper.sh`.
Sparkle auto-update keeps installed apps current between releases.

---

## What It Does

Plays a looping video or GIF as your desktop background.
Everything on your desktop still works normally -- the animation sits underneath.

| Source | How |
|--------|-----|
| **Video files** | `.mp4`, `.mov`, `.m4v` -- seamless looping, HEVC with alpha |
| **GIFs** | `.gif` -- native frame timing, loops continuously |
| **YouTube** | Paste a YouTube URL -- downloads and loops as wallpaper |
| **Apple Photos** | Pick a video or shuffle a random one from your library |

## Features

- **Resilient async loading** -- stale YouTube and Photos results are canceled or ignored so your newest wallpaper choice wins
- **Native macOS 27 design** -- system menus with SF Symbols, system alerts and system typography throughout; nothing is custom-drawn
- **Loading overlay** -- a Liquid Glass status panel floats above all windows so you always know what's happening
- **Playback errors** -- missing or unreadable files show an alert instead of a blank desktop
- **Per-desktop wallpapers** -- different wallpaper on each macOS Space and monitor, including separate Spaces per display
- **Sound control** -- mute or unmute video audio (muted by default)
- **Multi-monitor** -- auto-detects displays, adapts on hot-plug
- **Power-aware** -- pauses in place on Low Power Mode and thermal throttling
- **Automatic update checks** -- checks hourly via Sparkle using its standard updater dialog, with signed feeds and verify-before-extraction enabled in staged builds
- **Persistent** -- your wallpapers come back when you relaunch
- **Menu bar first** -- no Dock icon in normal use; one appears only while a dialog or update window is open
- **Dock fallback** -- if the menu bar hides the icon, open MovingPaper again: it shows a Dock icon whose menu has every command

## Menu

| Item | |
|------|---|
| **Choose File…** | Pick a `.gif`, `.mp4`, `.mov`, or `.m4v` |
| **Paste YouTube URL…** | Download a supported YouTube URL as wallpaper |
| **Choose from Photos…** | Pick a video from your Photos library |
| **Shuffle from Photos** | Random video from your entire library |
| **Remove MovingPaper** | Clear wallpaper |
| **Pause / Resume** | Stop or restart playback |
| **Turn Sound On / Off** | Toggle video audio |
| **Wallpaper per Desktop** | Give each Space and monitor its own wallpaper; off means one wallpaper everywhere |
| **Open at Login** | Start MovingPaper when you log in |
| **About MovingPaper** | Version and copyright |
| **YEN Terminal** | Open [yen.chat](https://yen.chat) |
| **GitHub Project** | Open this repository |
| **Check for Updates…** | Sparkle update check |
| **Quit MovingPaper** | Exit |

With **Wallpaper per Desktop** on, each Space and monitor gets its own wallpaper -- switch Spaces and the wallpaper changes with it, even when macOS is keeping separate active Spaces on different displays.

---

## Build from Source

Requires macOS 27 and Xcode 27.

```bash
git clone https://github.com/8bittts/movingpaper.git
cd movingpaper
swift test
./scripts/smoke-test.sh
./scripts/build_and_run.sh
```

The full script matrix, the release flow and the smoke-test contract are in [`_docs/05-infrastructure.md`](_docs/05-infrastructure.md) and [`_docs/09-quality.md`](_docs/09-quality.md).

Don't have any videos or GIFs on-hand?
The `videos/` folder ships with ten sample wallpapers you can load into MovingPaper to try it out.
More will be added over time.

---

## How It Works

A borderless `NSPanel` sits above the system wallpaper and below Finder icons, so the desktop stays interactive while video or GIF loops underneath.
The module map, the coordinator seams and the tech stack are in [`_docs/01-architecture.md`](_docs/01-architecture.md).

## Contributing

Fork, branch, `swift test`, PR.
One feature or fix per PR.

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
