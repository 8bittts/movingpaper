# Design System

Brand assets, the status-item mark, the overlay surface, typography and text patterns for MovingPaper.
The interface is built from system components and system styles; the brand lives in the marks, not in custom chrome.

## Marks

- The app icon is the Icon Composer document `build/MovingPaper.icon`: a full-bleed night-sky layer under a cloud-bank layer, which the system renders as Liquid Glass and from which it derives the dark, tinted and clear variants.
  `scripts/generate-icon-layers.swift` cuts both layers from the flattened art `build/movingpaper-1024.png`; run it only when the art changes.
  The build scripts compile the document with `actool` into the bundle's `Assets.car` ([05-infrastructure.md](05-infrastructure.md)); the app never sets its own icon at run time.
  `build/movingpaper.png` is the same art for the README.
- The menu-bar extra is the same icon in color, read from the bundle with `NSImage.applicationIconName` and drawn on a 22-point canvas, so the mark in the menu bar is about as tall as a standard glyph.
  It is a copy: resizing the shared image in place would shrink the icon in alerts too.
  An unbundled run (`swift run`, the test runner) has no icon and shows the template SF Symbol `cloud.moon.fill` instead.
- `scripts/generate-banner.swift` renders `build/banner.png`, and `build/movingpaper-dmg-background.png` with `build/dmg-background-opaque.png` back the DMG window.
- `build/yen.png` is the YEN credit image the README embeds.

## Overlay

`LoadingOverlayController` floats a small status panel above all windows while a wallpaper loads: a label over a system progress indicator.
The surface is Liquid Glass: an `NSGlassEffectView` in the regular style with a 20-point corner radius.
Regular glass, not clear, because the panel carries text and must stay legible over any wallpaper.
The surface is an AppKit view on purpose: it composites against what is behind the window, while a SwiftUI `glassEffect` in a transparent panel has nothing to sample and draws a flat slab.
`LoadingOverlayView` supplies only the content, so Reduce Transparency, Increase Contrast, light and dark appearance and Reduce Motion are handled by the system.

## Status menu

The status menu follows DockishOS's, in groups split by separators: the download in flight; the wallpaper and its sources, ending in Remove; Pause, Turn Sound On, Wallpaper per Desktop and Open at Login; About MovingPaper and YEN Terminal (https://yen.chat); GitHub Project and Check for Updates…; Quit MovingPaper.
Mode is one checkmark item, Wallpaper per Desktop, not a submenu: All Desktops is that item turned off.
About opens the standard About panel (icon, name, version and `NSHumanReadableCopyright`, "Copyright 2026 8BIT. MIT licensed."), not a custom alert.

## Menu symbols

The sources and Remove carry `folder`, `link`, `photo.on.rectangle`, `shuffle` and `trash`; the last three groups carry `info.circle`, `terminal`, `chevron.left.forwardslash.chevron.right`, `arrow.triangle.2.circlepath` and `power`, at 13 points and medium weight as in DockishOS.
The toggle group carries none, because its checkmarks show state.
A group has a symbol on every command or on none, and a `MenuSnapshot` test enforces it.
Measured on macOS 27.2: the status menu draws no item images at all, so the symbols are not visible there; the titles must carry the meaning on their own.

## Typography

Every text uses a system text style or a control's default font; no view sets a point size or a font design.
The overlay label is `.headline` with monospaced digits, so the panel does not change width as the percentage counts up.

## Text patterns

All copy is English.

| Surface                 | Pattern                                                                                       | Example                              |
| ----------------------- | --------------------------------------------------------------------------------------------- | ------------------------------------ |
| Menu item               | Title-style capitalization, no ending punctuation                                             | `Shuffle from Photos`                |
| Menu item needing input | A trailing ellipsis character, never three periods                                            | `Choose File…`                       |
| Toggled menu item       | A changeable label with a verb, or a checkmark for an attribute in effect                     | `Turn Sound Off`, `Wallpaper per Desktop` |
| Alert title             | A sentence fragment in title-style capitalization, no ending punctuation                      | `Download Failed`                    |
| Alert message           | Complete sentences, sentence-style capitalization, ending punctuation, contractions           | `The video couldn't be played.`      |
| Alert button            | One or two words naming the result; `OK` only when the alert is informational; always `Cancel` | `Download`                           |
| Progress status         | The activity, then the percentage or an ellipsis                                              | `Downloading 42%`, `Shuffling…`      |

An error message names what failed in the app's terms and, where the person can act, what to do next; it does not name internal tools.
`MenuBarLabelFormatter` formats menu titles and the download status that the menu and the overlay share, and `MenuSnapshot` tests assert the menu patterns.
The menu never advertises Settings, because no preferences UI exists (`AGENTS.md`).
