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
    var loginItem: LoginItemStatus
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
    case togglePerDesktop
    case checkForUpdates
    case about
    case openYen
    case openRepository
    case toggleOpenAtLogin
    case quit
}

struct MenuCommand: Equatable {
    var title: String
    var id: MenuCommandID
    var enabled: Bool = true
    var checked: Bool = false
    var displayID: CGDirectDisplayID? = nil
    var keyEquivalent: String = ""
    /// SF Symbol shown beside the title. Every command in a group has one or none does.
    var symbolName: String? = nil
}

enum MenuRow: Equatable {
    case disabled(String)
    case separator
    case sectionHeader(String)
    case command(MenuCommand)
    case submenu(title: String, checked: Bool = false, rows: [MenuRow])
}

/// Pure status-menu structure. `StatusBarController` turns these rows into `NSMenuItem`s.
enum MenuSnapshot {
    /// Groups, split by separators: the download in flight; the wallpaper and
    /// its sources; playback and app toggles; About and YEN Terminal; GitHub
    /// Project and Check for Updates…; Quit. The order of the last three groups
    /// follows DockishOS's status menu.
    static func rows(from input: MenuModelInput) -> [MenuRow] {
        var rows: [MenuRow] = []
        rows.append(contentsOf: downloadRows(progress: input.downloadProgress))
        rows.append(contentsOf: sourceRows(from: input))
        rows.append(.separator)
        rows.append(contentsOf: toggleRows(from: input))
        rows.append(.separator)
        rows.append(contentsOf: footerRows(from: input))
        return rows
    }

    /// The status-menu rows for the Dock icon's menu, without Quit: the Dock
    /// supplies its own.
    static func dockRows(from input: MenuModelInput) -> [MenuRow] {
        var rows = rows(from: input)
        if case .command(let last) = rows.last, last.id == .quit {
            rows.removeLast()
        }
        if rows.last == .separator {
            rows.removeLast()
        }
        return rows
    }

    private static func downloadRows(progress: Double?) -> [MenuRow] {
        guard let progress else { return [] }
        return [
            .disabled(MenuBarLabelFormatter.downloadStatus(progress: progress)),
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
        }
        rows.append(contentsOf: sourceCommands(displayID: nil, includeRemove: false))
        if input.sharedFileName != nil {
            rows.append(.command(MenuCommand(title: "Remove MovingPaper", id: .clearAll, symbolName: "trash")))
        }
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
            rows.append(.command(MenuCommand(title: "Remove All MovingPapers", id: .clearAll, symbolName: "trash")))
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
        let rows: [MenuRow] = space.isCurrent
            ? sourceCommands(displayID: displayID, includeRemove: space.fileName != nil)
            : [.disabled("Switch to This Desktop to Change")]
        return .submenu(title: label, checked: space.isCurrent, rows: rows)
    }

    private static func sourceCommands(
        displayID: CGDirectDisplayID?,
        includeRemove: Bool
    ) -> [MenuRow] {
        var rows: [MenuRow] = [
            .command(MenuCommand(
                title: "Choose File…", id: .chooseFile, displayID: displayID, symbolName: "folder"
            )),
            .command(MenuCommand(
                title: "Paste YouTube URL…", id: .pasteYouTube, displayID: displayID, symbolName: "link"
            )),
            .command(MenuCommand(
                title: "Choose from Photos…", id: .choosePhotos, displayID: displayID, symbolName: "photo.on.rectangle"
            )),
            .command(MenuCommand(
                title: "Shuffle from Photos", id: .shufflePhotos, displayID: displayID, symbolName: "shuffle"
            )),
        ]
        if includeRemove {
            rows.append(.command(MenuCommand(
                title: "Remove", id: .clearDisplay, displayID: displayID, symbolName: "trash"
            )))
        }
        return rows
    }

    /// Playback and app toggles. Mode is one checkmark item rather than a
    /// two-item submenu: All Desktops is simply Per Desktop turned off.
    private static func toggleRows(from input: MenuModelInput) -> [MenuRow] {
        var rows: [MenuRow] = []
        if input.hasAnyWallpaper {
            rows.append(.command(MenuCommand(
                title: input.isPaused ? "Resume" : "Pause",
                id: .togglePause
            )))
        }
        rows.append(.command(MenuCommand(
            title: input.isMuted ? "Turn Sound On" : "Turn Sound Off",
            id: .toggleMute
        )))
        rows.append(.command(MenuCommand(
            title: "Wallpaper per Desktop",
            id: .togglePerDesktop,
            checked: input.mode == .perDesktop
        )))
        rows.append(.command(loginItemCommand(input.loginItem)))
        return rows
    }

    /// A login item waiting on approval opens System Settings, so its title
    /// names that step and ends in an ellipsis.
    private static func loginItemCommand(_ status: LoginItemStatus) -> MenuCommand {
        switch status {
        case .enabled:
            MenuCommand(title: "Open at Login", id: .toggleOpenAtLogin, checked: true)
        case .disabled:
            MenuCommand(title: "Open at Login", id: .toggleOpenAtLogin)
        case .requiresApproval:
            MenuCommand(title: "Allow Open at Login…", id: .toggleOpenAtLogin)
        }
    }

    private static func footerRows(from input: MenuModelInput) -> [MenuRow] {
        [
            .command(MenuCommand(title: "About MovingPaper", id: .about, symbolName: "info.circle")),
            .command(MenuCommand(title: "YEN Terminal", id: .openYen, symbolName: "terminal")),
            .separator,
            .command(MenuCommand(
                title: "GitHub Project",
                id: .openRepository,
                symbolName: "chevron.left.forwardslash.chevron.right"
            )),
            .command(MenuCommand(
                title: "Check for Updates…",
                id: .checkForUpdates,
                enabled: input.canCheckForUpdates,
                symbolName: "arrow.triangle.2.circlepath"
            )),
            .separator,
            // The app has no Dock icon, so this is the only way to quit it.
            .command(MenuCommand(title: "Quit MovingPaper", id: .quit, keyEquivalent: "q", symbolName: "power")),
        ]
    }
}
