# MovingPaper

Animated wallpaper engine for macOS -- GIFs, MOV, MP4 as desktop backgrounds.

## Requirements

- macOS 15.0+ (Sequoia)
- Swift 6.0+

## Build & Run

```bash
swift build
swift run MovingPaper
```

The app runs as a menu bar icon (no Dock icon). Click the status bar icon to:
- Choose a GIF or video file
- Pause / Resume playback
- Remove the wallpaper

## Architecture

| File | Purpose |
|------|---------|
| `MovingPaperApp.swift` | SwiftUI @main entry, Settings scene |
| `AppDelegate.swift` | NSApplicationDelegate, .accessory activation policy |
| `WallpaperPanel.swift` | Borderless NSPanel at desktop window level |
| `WallpaperWindowController.swift` | Per-screen panel + content hosting |
| `WallpaperManager.swift` | Central coordinator: files, screens, power state |
| `VideoWallpaperView.swift` | AVQueuePlayer + AVPlayerLooper for .mov/.mp4 |
| `GIFWallpaperView.swift` | CGAnimateImageAtURLWithBlock for .gif |
| `StatusBarController.swift` | NSStatusItem menu with controls |
| `SettingsView.swift` | Settings window (placeholder) |

## How It Works

1. Creates a borderless `NSPanel` at `CGWindowLevelForKey(.desktopWindow) + 1` -- between the desktop background and Finder icons
2. `ignoresMouseEvents = true` so desktop icons stay clickable
3. Video loops seamlessly via `AVPlayerLooper`; GIFs animate via `CGAnimateImageAtURLWithBlock`
4. One window per connected display, rebuilt on screen changes
5. Auto-pauses on Low Power Mode or thermal throttling (.serious/.critical)

## Tech Stack

- Swift Package Manager (no Xcode project needed)
- AppKit for windowing (NSPanel, NSStatusItem)
- SwiftUI for UI construction
- AVFoundation for video playback
- ImageIO for GIF animation
- CoreGraphics for desktop window levels

## License

MIT
