# MovingPaper

A native macOS menu bar app that plays GIFs and video files as animated desktop wallpapers.

---

## What is MovingPaper?

MovingPaper places animated content behind your desktop icons using a borderless window at the macOS desktop level. Your desktop stays fully interactive -- icons, right-click menus, and drag-and-drop all work normally.

- **Video wallpapers** -- seamless looping of `.mov`, `.mp4`, `.m4v` (including HEVC with alpha)
- **GIF wallpapers** -- native frame-timed animation via ImageIO
- **Multi-monitor** -- one wallpaper window per connected display, auto-rebuilt on hot-plug
- **Power-aware** -- auto-pauses on Low Power Mode and thermal throttling (serious/critical)
- **Menu bar app** -- no Dock icon, no Cmd + Tab entry, lives in the status bar

---

## System Requirements

- macOS 15.0+ (Sequoia)
- Swift 6.0+

---

## Build & Run

```bash
swift build
swift run MovingPaper
```

The app appears as a photo icon in the menu bar. Click it to:

- **Choose File...** -- pick a GIF or video file
- **Pause / Resume** -- toggle playback
- **Remove Wallpaper** -- clear and tear down windows
- **Quit MovingPaper** -- exit the app

---

## Project Structure

```
moving-paper/
├── Package.swift                           # SPM config, macOS 15+, Swift 6.0
└── Sources/MovingPaper/
    ├── MovingPaperApp.swift                # SwiftUI @main entry, Settings scene
    ├── AppDelegate.swift                   # .accessory activation, bootstraps manager + status bar
    ├── WallpaperPanel.swift                # Borderless NSPanel at desktopWindow+1 level
    ├── WallpaperWindowController.swift     # Per-screen panel + SwiftUI content hosting
    ├── WallpaperManager.swift              # Central coordinator: files, screens, power state
    ├── VideoWallpaperView.swift            # AVQueuePlayer + AVPlayerLooper
    ├── GIFWallpaperView.swift              # CGAnimateImageAtURLWithBlock
    ├── StatusBarController.swift           # NSStatusItem with file picker + controls
    ├── SettingsView.swift                  # Settings window (placeholder)
    └── Resources/
        └── Info.plist                      # Bundle config, LSUIElement
```

---

## How It Works

1. A borderless `NSPanel` is placed at `CGWindowLevelForKey(.desktopWindow) + 1` -- between the system desktop background and Finder's icon layer
2. `ignoresMouseEvents = true` makes the window invisible to clicks so desktop icons stay interactive
3. Video loops seamlessly via `AVQueuePlayer` + `AVPlayerLooper`; GIFs animate frame-by-frame via `CGAnimateImageAtURLWithBlock`
4. One window per connected display, rebuilt automatically on `didChangeScreenParametersNotification`
5. `ProcessInfo.isLowPowerModeEnabled` and `ProcessInfo.thermalState` gate playback to avoid wasting energy when the system is constrained

---

## Tech Stack

| Layer | Technology |
|-------|------------|
| Build system | Swift Package Manager |
| Windowing | AppKit (NSPanel, NSStatusItem, NSScreen) |
| UI | SwiftUI via NSHostingView |
| Video playback | AVFoundation (AVQueuePlayer, AVPlayerLooper, AVPlayerLayer) |
| GIF animation | ImageIO (CGAnimateImageAtURLWithBlock) |
| Desktop level | CoreGraphics (CGWindowLevelForKey) |

All public Apple APIs -- no private frameworks.

---

## License

MIT
