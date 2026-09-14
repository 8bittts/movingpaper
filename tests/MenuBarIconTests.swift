import Testing
import AppKit
@testable import MovingPaper

struct MenuBarIconTests {

    @Test @MainActor func iconRendersWithPositiveSize() {
        let icon = MenuBarIcon.brandIcon()
        #expect(icon.size == MenuBarIcon.pointSize)
    }

    @Test @MainActor func brandIconIsATemplateSymbol() {
        let icon = MenuBarIcon.brandIcon()
        #expect(icon.isTemplate == true)
        #expect(icon.representations.isEmpty == false)
    }

    @Test @MainActor func iconScalesCorrectly() {
        let icon = MenuBarIcon.brandIcon()
        #expect(icon.size.width == 18)
        #expect(icon.size.height == 18)
    }

    @Test @MainActor func applicationIconKeepsColourArtwork() {
        let icon = MenuBarIcon.applicationIcon()
        #expect(icon != nil)
        #expect(icon?.isTemplate == false)
    }
}
