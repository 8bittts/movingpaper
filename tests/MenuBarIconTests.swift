import AppKit
import Testing
@testable import MovingPaper

struct MenuBarIconTests {

    @Test func brandIconIsATemplateSymbol() {
        let icon = MenuBarIcon.brandIcon()
        #expect(icon.isTemplate)
        #expect(!icon.representations.isEmpty)
        #expect(icon.accessibilityDescription == "MovingPaper")
    }

    /// `cloud.moon.fill` is wider than tall. A forced square size stretched it
    /// in the menu bar, so the icon must keep the symbol's own proportions.
    @Test func brandIconKeepsTheSymbolProportions() throws {
        let symbol = try #require(NSImage(systemSymbolName: "cloud.moon.fill", accessibilityDescription: nil))
        let icon = MenuBarIcon.brandIcon()
        #expect(icon.size == symbol.size)
        #expect(icon.size.width > icon.size.height)
    }
}
