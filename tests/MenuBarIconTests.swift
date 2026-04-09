import Testing
import AppKit
@testable import MovingPaper

struct MenuBarIconTests {

    @Test @MainActor func iconRendersWithPositiveSize() {
        let icon = MenuBarIcon.brandIcon()
        #expect(icon.size == MenuBarIcon.pointSize)
    }

    @Test @MainActor func brandIconUsesBundledArtwork() {
        let icon = MenuBarIcon.brandIcon()
        #expect(icon.isTemplate == false)
        #expect(icon.representations.isEmpty == false)
    }

    @Test @MainActor func iconScalesCorrectly() {
        let icon = MenuBarIcon.brandIcon()
        #expect(icon.size.width == 22)
        #expect(icon.size.height == 22)
    }
}
