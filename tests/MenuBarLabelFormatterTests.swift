import Testing
@testable import MovingPaper

struct MenuBarLabelFormatterTests {

    @Test func sharedWallpaperTitleStaysWithinTheMenuLimit() {
        let title = MenuBarLabelFormatter.sharedWallpaperTitle(
            fileName: "this-is-a-very-long-wallpaper-file-name.mp4"
        )

        #expect(title.count <= MenuBarLabelFormatter.maxVisibleCharacters)
        #expect(title.contains("…"))
        #expect(title.hasSuffix(".mp4"))
    }

    @Test func desktopWallpaperTitlePreservesTheDesktopPrefix() {
        let title = MenuBarLabelFormatter.desktopWallpaperTitle(
            index: 3,
            fileName: "another-extremely-long-file-name.gif"
        )

        #expect(title.count <= MenuBarLabelFormatter.maxVisibleCharacters)
        #expect(title.hasPrefix("Desktop 3: "))
        #expect(title.contains("…"))
        #expect(title.hasSuffix(".gif"))
    }
}
