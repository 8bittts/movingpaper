import CoreGraphics
import AppKit
import Testing
@testable import MovingPaper

struct MenuSnapshotTests {

    private let displayA: CGDirectDisplayID = 11
    private let displayB: CGDirectDisplayID = 22

    @Test func downloadProgressInsertsCancelBeforeTheSourceSection() {
        let rows = MenuSnapshot.rows(from: baseInput(downloadProgress: 0.42))
        #expect(rows[0] == .disabled("Downloading 42%"))
        #expect(command(rows[1])?.id == .cancelDownload)
        #expect(rows[2] == .separator)
        #expect(command(rows[3])?.id == .chooseFile)
    }

    @Test func allDesktopsWithoutWallpaperOffersTheFourSources() {
        let ids = sourceIDs(MenuSnapshot.rows(from: baseInput()))
        #expect(ids == [.chooseFile, .pasteYouTube, .choosePhotos, .shufflePhotos])
    }

    @Test func allDesktopsWithWallpaperShowsFilenameAndRemove() {
        var input = baseInput()
        input.sharedFileName = "loop.mp4"
        input.hasAnyWallpaper = true
        let rows = MenuSnapshot.rows(from: input)

        #expect(rows[0] == .disabled("loop.mp4"))
        // Remove closes the source group, with no separators around the file name.
        #expect(command(rows[5])?.title == "Remove MovingPaper")
        #expect(command(rows[5])?.id == .clearAll)
        #expect(rows[6] == .separator)
        #expect(containsCommand(rows, id: .togglePause, title: "Pause"))
    }

    @Test func soundAndModeTitlesFollowLiveState() {
        var input = baseInput()
        input.isMuted = false
        input.mode = .perDesktop
        input.displays = []
        let rows = MenuSnapshot.rows(from: input)

        #expect(containsCommand(rows, id: .toggleMute, title: "Turn Sound Off"))
        #expect(firstCommand(rows, id: .togglePerDesktop)?.title == "Wallpaper per Desktop")
        #expect(firstCommand(rows, id: .togglePerDesktop)?.checked == true)
        #expect(firstCommand(MenuSnapshot.rows(from: baseInput()), id: .togglePerDesktop)?.checked == false)
    }

    /// Normalized to DockishOS: About and YEN Terminal, then GitHub Project and
    /// Check for Updates…, then Quit, each group split by a separator.
    @Test func footerFollowsTheDockishOSStatusMenu() {
        let rows = MenuSnapshot.rows(from: baseInput())
        let footer = Array(rows.suffix(7))
        #expect(footer.map { command($0)?.id } == [
            .about, .openYen, nil, .openRepository, .checkForUpdates, nil, .quit,
        ])
        #expect(footer[2] == .separator && footer[5] == .separator)
        #expect(commandTitles(footer) == [
            "About MovingPaper", "YEN Terminal", "GitHub Project", "Check for Updates…", "Quit MovingPaper",
        ])
    }

    @Test func playbackAndAppTogglesShareOneGroup() {
        var input = baseInput()
        input.hasAnyWallpaper = true
        input.sharedFileName = "loop.mp4"
        let groups = MenuSnapshot.rows(from: input).split(separator: .separator)
        let toggles = groups[1].compactMap { command($0)?.id }
        #expect(toggles == [.togglePause, .toggleMute, .togglePerDesktop, .toggleOpenAtLogin])
        #expect(groups.count == 5)
    }

    @Test func perDesktopWithNoDisplaysShowsAPlaceholder() {
        var input = baseInput()
        input.mode = .perDesktop
        input.displays = []
        let rows = MenuSnapshot.rows(from: input)
        #expect(rows.contains(.disabled("No Displays")))
        #expect(!containsCommand(rows, id: .chooseFile))
    }

    @Test func perDesktopCurrentSpaceGetsSourceActionsAndOthersDoNot() {
        var input = baseInput()
        input.mode = .perDesktop
        input.hasAnyWallpaper = true
        input.displays = [
            DisplayMenuInput(
                id: displayA,
                name: "Built-in",
                spaces: [
                    SpaceMenuInput(fileName: "a.mp4", isCurrent: true),
                    SpaceMenuInput(fileName: nil, isCurrent: false),
                ]
            ),
        ]
        let rows = MenuSnapshot.rows(from: input)

        guard case .submenu(let currentTitle, let currentChecked, let currentChildren) = rows[0] else {
            Issue.record("Expected current-space item")
            return
        }
        #expect(currentTitle.hasPrefix("Desktop 1: "))
        #expect(currentChecked)
        #expect(command(currentChildren[0])?.id == .chooseFile)
        #expect(command(currentChildren[0])?.displayID == displayA)
        #expect(command(currentChildren[4])?.id == .clearDisplay)

        guard case .submenu(_, let otherChecked, let otherChildren) = rows[1] else {
            Issue.record("Expected other-space item")
            return
        }
        #expect(!otherChecked)
        #expect(otherChildren == [.disabled("Switch to This Desktop to Change")])
        #expect(containsCommand(rows, id: .clearAll, title: "Remove All MovingPapers"))
    }

    @Test func multipleDisplaysGetSectionHeaders() {
        var input = baseInput()
        input.mode = .perDesktop
        input.displays = [
            DisplayMenuInput(id: displayA, name: "Built-in Retina Display", spaces: [
                SpaceMenuInput(fileName: nil, isCurrent: true),
            ]),
            DisplayMenuInput(id: displayB, name: "Studio Display", spaces: [
                SpaceMenuInput(fileName: nil, isCurrent: true),
            ]),
        ]
        let rows = MenuSnapshot.rows(from: input)
        #expect(rows[0] == .sectionHeader("Built-in Retina Display"))
        #expect(rows.contains(.separator))
        #expect(rows.contains(.sectionHeader("Studio Display")))
    }

    @Test func updateTitleHonorsTheEnabledFlag() {
        var input = baseInput()
        input.canCheckForUpdates = false
        let rows = MenuSnapshot.rows(from: input)
        let update = firstCommand(rows, id: .checkForUpdates)
        #expect(update?.title == "Check for Updates…")
        #expect(update?.enabled == false)

        input.canCheckForUpdates = true
        let enabled = firstCommand(MenuSnapshot.rows(from: input), id: .checkForUpdates)
        #expect(enabled?.title == "Check for Updates…")
        #expect(enabled?.enabled == true)
    }

    @Test func footerPutsAboutAndOpenAtLoginNextToUpdates() {
        var input = baseInput()
        input.loginItem = .enabled
        let rows = MenuSnapshot.rows(from: input)
        #expect(containsCommand(rows, id: .about, title: "About MovingPaper"))
        let login = firstCommand(rows, id: .toggleOpenAtLogin)
        #expect(login?.title == "Open at Login")
        #expect(login?.checked == true)
        #expect(commandTitles(rows).contains("Built with YEN") == false)
    }

    @Test func aLoginItemAwaitingApprovalPointsToSystemSettings() {
        var input = baseInput()
        input.loginItem = .requiresApproval
        let login = firstCommand(MenuSnapshot.rows(from: input), id: .toggleOpenAtLogin)
        #expect(login?.title == "Allow Open at Login…")
        #expect(login?.checked == false)
    }

    @Test func mutedStateOffersTurnSoundOn() {
        let rows = MenuSnapshot.rows(from: baseInput())
        #expect(containsCommand(rows, id: .toggleMute, title: "Turn Sound On"))
    }

    @Test func quitKeepsTheQKeyEquivalent() {
        let quit = firstCommand(MenuSnapshot.rows(from: baseInput()), id: .quit)
        #expect(quit?.title == "Quit MovingPaper")
        #expect(quit?.keyEquivalent == "q")
    }

    // MARK: - Design conventions (Human Interface Guidelines: Menus)

    /// A fully populated menu in both modes, so every label and symbol is covered.
    private func everyRow() -> [MenuRow] {
        everyMenu().flatMap { $0 }
    }

    private func everyMenu() -> [[MenuRow]] {
        var input = baseInput(downloadProgress: 0.42)
        input.hasAnyWallpaper = true
        input.sharedFileName = "clip.mp4"
        let allDesktops = MenuSnapshot.rows(from: input)
        input.mode = .perDesktop
        input.displays = [
            DisplayMenuInput(id: 1, name: "Built-in", spaces: [
                SpaceMenuInput(fileName: "a.mp4", isCurrent: true),
                SpaceMenuInput(fileName: nil, isCurrent: false),
            ]),
            DisplayMenuInput(id: 2, name: "Studio Display", spaces: [
                SpaceMenuInput(fileName: nil, isCurrent: true),
            ]),
        ]
        return [allDesktops, MenuSnapshot.rows(from: input)]
    }

    private func everyCommand(_ rows: [MenuRow]) -> [MenuCommand] {
        rows.flatMap { row -> [MenuCommand] in
            switch row {
            case .command(let command): [command]
            case .submenu(_, _, let children): everyCommand(children)
            default: []
            }
        }
    }

    /// "Provide icons for all menu items in a group, or none of them."
    @Test func symbolsAreUniformWithinEachGroup() {
        func check(_ rows: [MenuRow]) {
            for group in rows.split(separator: .separator) {
                let commands = group.compactMap { command($0) }
                let withSymbol = commands.filter { $0.symbolName != nil }
                #expect(
                    withSymbol.isEmpty || withSymbol.count == commands.count,
                    "mixed symbols in group: \(commands.map(\.title))"
                )
                for row in group {
                    if case .submenu(_, _, let children) = row { check(children) }
                }
            }
        }
        for menu in everyMenu() {
            check(menu)
        }
    }

    @Test @MainActor func everySymbolNameIsARealSFSymbol() {
        let names = Set(everyCommand(everyRow()).compactMap(\.symbolName))
        #expect(names == [
            "folder", "link", "photo.on.rectangle", "shuffle", "trash",
            "info.circle", "terminal", "chevron.left.forwardslash.chevron.right",
            "arrow.triangle.2.circlepath", "power",
        ])
        for name in names {
            #expect(
                NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil,
                "unknown SF Symbol: \(name)"
            )
        }
    }

    /// Labels use title-style capitalization, never end in a period, and use the
    /// ellipsis character (not three periods) only as a trailing "needs more input" mark.
    @Test func labelsFollowTheMenuTextPattern() {
        let lowercaseWords: Set<String> = ["a", "an", "the", "and", "or", "at", "by", "for", "from", "in", "of", "on", "per", "to"]
        // File names and display names are user content, not copy.
        let titles = commandTitles(everyRow()).filter { !$0.contains(".mp4") && $0 != "Built-in" && $0 != "Studio Display" }
        #expect(titles.count > 20)
        for title in titles {
            #expect(!title.hasSuffix("."), "ends with a period: \(title)")
            #expect(!title.contains("..."), "three periods instead of an ellipsis: \(title)")
            #expect(!title.dropLast().contains("…"), "ellipsis is not trailing: \(title)")
            #expect(!title.contains(":") || title.hasPrefix("Desktop "), "stray colon: \(title)")
            let words = title.replacingOccurrences(of: "…", with: "").split(separator: " ").map(String.init)
            for (index, word) in words.enumerated() {
                guard let first = word.first, first.isLetter else { continue }
                let isEdge = index == 0 || index == words.count - 1
                if lowercaseWords.contains(word.lowercased()), !isEdge {
                    #expect(first.isLowercase, "\(word) should be lowercase in: \(title)")
                } else {
                    #expect(first.isUppercase, "\(word) should be capitalized in: \(title)")
                }
            }
        }
    }

    @Test func dockRowsDropQuitAndItsSeparator() {
        let full = MenuSnapshot.rows(from: baseInput())
        let dock = MenuSnapshot.dockRows(from: baseInput())
        #expect(dock == Array(full.dropLast(2)))
        #expect(command(dock[dock.count - 1])?.id == .checkForUpdates)
        #expect(!dock.contains { command($0)?.id == .quit })
    }

    private func baseInput(downloadProgress: Double? = nil) -> MenuModelInput {
        MenuModelInput(
            downloadProgress: downloadProgress,
            mode: .allDesktops,
            isMuted: true,
            isPaused: false,
            hasAnyWallpaper: false,
            sharedFileName: nil,
            canCheckForUpdates: true,
            loginItem: .disabled,
            displays: []
        )
    }

    private func command(_ row: MenuRow) -> MenuCommand? {
        if case .command(let command) = row { return command }
        return nil
    }

    private func sourceIDs(_ rows: [MenuRow]) -> [MenuCommandID] {
        rows.compactMap { row -> MenuCommandID? in
            guard let command = command(row) else { return nil }
            switch command.id {
            case .chooseFile, .pasteYouTube, .choosePhotos, .shufflePhotos:
                return command.id
            default:
                return nil
            }
        }
    }

    private func containsCommand(_ rows: [MenuRow], id: MenuCommandID, title: String? = nil) -> Bool {
        firstCommand(rows, id: id).map { title == nil || $0.title == title } ?? false
    }

    private func commandTitles(_ rows: [MenuRow]) -> [String] {
        rows.flatMap { row -> [String] in
            switch row {
            case .command(let command):
                return [command.title]
            case .submenu(let title, _, let children):
                return [title] + commandTitles(children)
            case .disabled(let title), .sectionHeader(let title):
                return [title]
            case .separator:
                return []
            }
        }
    }

    private func firstCommand(_ rows: [MenuRow], id: MenuCommandID) -> MenuCommand? {
        for row in rows {
            switch row {
            case .command(let command) where command.id == id:
                return command
            case .submenu(_, _, let children):
                if let found = firstCommand(children, id: id) { return found }
            default:
                continue
            }
        }
        return nil
    }
}
