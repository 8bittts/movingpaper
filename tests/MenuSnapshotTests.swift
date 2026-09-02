import CoreGraphics
import Testing
@testable import MovingPaper

struct MenuSnapshotTests {

    private let displayA: CGDirectDisplayID = 11
    private let displayB: CGDirectDisplayID = 22

    @Test func downloadProgressInsertsCancelBeforeTheSourceSection() {
        let rows = MenuSnapshot.rows(from: baseInput(downloadProgress: 0.42))
        #expect(rows[0] == .disabled("Downloading: 42%…"))
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
        #expect(command(rows[2])?.title == "Remove MovingPaper")
        #expect(command(rows[2])?.id == .clearAll)
        #expect(containsCommand(rows, id: .togglePause, title: "Pause"))
    }

    @Test func soundAndModeTitlesFollowLiveState() {
        var input = baseInput()
        input.isMuted = false
        input.mode = .perDesktop
        input.displays = []
        let rows = MenuSnapshot.rows(from: input)

        #expect(containsCommand(rows, id: .toggleMute, title: "Sound: On"))
        guard case .submenu(let title, let modeRows) = rows.first(where: {
            if case .submenu = $0 { return true }
            return false
        }) else {
            Issue.record("Missing mode submenu")
            return
        }
        #expect(title == "MovingPaper Mode")
        #expect(command(modeRows[0])?.checked == false)
        #expect(command(modeRows[1])?.checked == true)
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

        guard case .item(let currentTitle, let currentChecked, let currentChildren) = rows[0] else {
            Issue.record("Expected current-space item")
            return
        }
        #expect(currentTitle.hasPrefix("Desktop 1: "))
        #expect(currentChecked)
        #expect(command(currentChildren[0])?.id == .chooseFile)
        #expect(command(currentChildren[0])?.displayID == displayA)
        #expect(command(currentChildren[4])?.id == .clearDisplay)

        guard case .item(_, let otherChecked, let otherChildren) = rows[1] else {
            Issue.record("Expected other-space item")
            return
        }
        #expect(!otherChecked)
        #expect(otherChildren == [.disabled("Switch to this desktop to change")])
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

    @Test func updateTitleIncludesVersionAndHonorsTheEnabledFlag() {
        var input = baseInput()
        input.appVersion = "0.040"
        input.canCheckForUpdates = false
        let rows = MenuSnapshot.rows(from: input)
        let update = firstCommand(rows, id: .checkForUpdates)
        #expect(update?.title == "Check for Updates (v0.040)…")
        #expect(update?.enabled == false)

        input.appVersion = ""
        input.canCheckForUpdates = true
        let untitled = firstCommand(MenuSnapshot.rows(from: input), id: .checkForUpdates)
        #expect(untitled?.title == "Check for Updates…")
        #expect(untitled?.enabled == true)
    }

    @Test func quitKeepsTheQKeyEquivalent() {
        let quit = firstCommand(MenuSnapshot.rows(from: baseInput()), id: .quit)
        #expect(quit?.title == "Quit MovingPaper")
        #expect(quit?.keyEquivalent == "q")
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
            appVersion: "0.040",
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

    private func firstCommand(_ rows: [MenuRow], id: MenuCommandID) -> MenuCommand? {
        for row in rows {
            switch row {
            case .command(let command) where command.id == id:
                return command
            case .submenu(_, let children), .item(_, _, let children):
                if let found = firstCommand(children, id: id) { return found }
            default:
                continue
            }
        }
        return nil
    }
}
