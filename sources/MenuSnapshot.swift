import CoreGraphics
import Foundation

/// Inputs the status menu needs from live wallpaper and updater state.
/// Built by `WallpaperManager`; rendered by `StatusBarController`.
struct MenuModelInput: Equatable {
    var downloadProgress: Double?
    var mode: WallpaperMode
    var isMuted: Bool
    var isPaused: Bool
    var hasAnyWallpaper: Bool
    var sharedFileName: String?
    var canCheckForUpdates: Bool
    var appVersion: String
    var displays: [DisplayMenuInput]
}

struct DisplayMenuInput: Equatable {
    var id: CGDirectDisplayID
    var name: String
    var spaces: [SpaceMenuInput]
}

struct SpaceMenuInput: Equatable {
    var fileName: String?
    var isCurrent: Bool
}

enum MenuCommandID: Equatable {
    case cancelDownload
    case chooseFile
    case pasteYouTube
    case choosePhotos
    case shufflePhotos
    case clearAll
    case clearDisplay
    case toggleMute
    case togglePause
    case setModeAllDesktops
    case setModePerDesktop
    case checkForUpdates
    case openYEN
    case quit
}

struct MenuCommand: Equatable {
    var title: String
    var id: MenuCommandID
    var enabled: Bool = true
    var checked: Bool = false
    var displayID: CGDirectDisplayID? = nil
    var keyEquivalent: String = ""
}

enum MenuRow: Equatable {
    case disabled(String)
    case separator
    case sectionHeader(String)
    case command(MenuCommand)
    case submenu(title: String, rows: [MenuRow])
    case item(title: String, checked: Bool, children: [MenuRow])
}

/// Pure status-menu structure. `StatusBarController` turns these rows into `NSMenuItem`s.
enum MenuSnapshot {
    static func rows(from input: MenuModelInput) -> [MenuRow] {
        var rows: [MenuRow] = []
        rows.append(contentsOf: downloadRows(progress: input.downloadProgress))
        rows.append(contentsOf: sourceRows(from: input))
        rows.append(.separator)
        rows.append(contentsOf: playbackRows(from: input))
        rows.append(.separator)
        rows.append(contentsOf: footerRows(from: input))
        return rows
    }

    private static func downloadRows(progress: Double?) -> [MenuRow] {
        guard let progress else { return [] }
        let pct = Int(progress * 100)
        return [
            .disabled("Downloading: \(pct)%…"),
            .command(MenuCommand(title: "Cancel Download", id: .cancelDownload)),
            .separator,
        ]
    }

    private static func sourceRows(from input: MenuModelInput) -> [MenuRow] {
        switch input.mode {
        case .allDesktops:
            return allDesktopsRows(from: input)
        case .perDesktop:
            return perDesktopRows(from: input)
        }
    }

    private static func allDesktopsRows(from input: MenuModelInput) -> [MenuRow] {
        var rows: [MenuRow] = []
        if let fileName = input.sharedFileName {
            rows.append(.disabled(MenuBarLabelFormatter.sharedWallpaperTitle(fileName: fileName)))
            rows.append(.separator)
            rows.append(.command(MenuCommand(title: "Remove MovingPaper", id: .clearAll)))
            rows.append(.separator)
        }
        rows.append(contentsOf: sourceCommands(displayID: nil, includeRemove: false))
        return rows
    }

    private static func perDesktopRows(from input: MenuModelInput) -> [MenuRow] {
        let displays = input.displays
        if displays.isEmpty {
            return [.disabled("No Displays")]
        }

        var rows: [MenuRow] = []
        for (displayIndex, display) in displays.enumerated() {
            if displays.count > 1 {
                rows.append(.sectionHeader(MenuBarLabelFormatter.displayHeaderTitle(display.name)))
            }
            for (index, space) in display.spaces.enumerated() {
                rows.append(spaceRow(space, index: index + 1, displayID: display.id))
            }
            if displayIndex < displays.count - 1 {
                rows.append(.separator)
            }
        }
        if input.hasAnyWallpaper {
            rows.append(.separator)
            rows.append(.command(MenuCommand(title: "Remove All MovingPapers", id: .clearAll)))
        }
        return rows
    }

    private static func spaceRow(
        _ space: SpaceMenuInput,
        index: Int,
        displayID: CGDirectDisplayID
    ) -> MenuRow {
        let label = MenuBarLabelFormatter.desktopWallpaperTitle(
            index: index,
            fileName: space.fileName ?? "No MovingPaper"
        )
        let children: [MenuRow]
        if space.isCurrent {
            children = sourceCommands(
                displayID: displayID,
                includeRemove: space.fileName != nil
            )
        } else {
            children = [.disabled("Switch to this desktop to change")]
        }
        return .item(title: label, checked: space.isCurrent, children: children)
    }

    private static func sourceCommands(
        displayID: CGDirectDisplayID?,
        includeRemove: Bool
    ) -> [MenuRow] {
        var rows: [MenuRow] = [
            .command(MenuCommand(title: "Choose File…", id: .chooseFile, displayID: displayID)),
            .command(MenuCommand(title: "Paste YouTube URL…", id: .pasteYouTube, displayID: displayID)),
            .command(MenuCommand(title: "Choose from Photos…", id: .choosePhotos, displayID: displayID)),
            .command(MenuCommand(title: "Shuffle from Photos", id: .shufflePhotos, displayID: displayID)),
        ]
        if includeRemove {
            rows.append(.command(MenuCommand(title: "Remove", id: .clearDisplay, displayID: displayID)))
        }
        return rows
    }

    private static func playbackRows(from input: MenuModelInput) -> [MenuRow] {
        var rows: [MenuRow] = [
            .command(MenuCommand(
                title: input.isMuted ? "Sound: Off" : "Sound: On",
                id: .toggleMute
            )),
            .submenu(title: "MovingPaper Mode", rows: [
                .command(MenuCommand(
                    title: "All Desktops",
                    id: .setModeAllDesktops,
                    checked: input.mode == .allDesktops
                )),
                .command(MenuCommand(
                    title: "Per Desktop",
                    id: .setModePerDesktop,
                    checked: input.mode == .perDesktop
                )),
            ]),
        ]
        if input.hasAnyWallpaper {
            rows.append(.separator)
            rows.append(.command(MenuCommand(
                title: input.isPaused ? "Resume" : "Pause",
                id: .togglePause
            )))
        }
        return rows
    }

    private static func footerRows(from input: MenuModelInput) -> [MenuRow] {
        let updateTitle = input.appVersion.isEmpty
            ? "Check for Updates…"
            : "Check for Updates (v\(input.appVersion))…"
        return [
            .command(MenuCommand(
                title: updateTitle,
                id: .checkForUpdates,
                enabled: input.canCheckForUpdates
            )),
            .command(MenuCommand(title: "Built with YEN", id: .openYEN)),
            .separator,
            .command(MenuCommand(title: "Quit MovingPaper", id: .quit, keyEquivalent: "q")),
        ]
    }
}
