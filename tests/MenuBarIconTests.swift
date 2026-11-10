import AppKit
import Testing
@testable import MovingPaper

struct MenuBarIconTests {

    /// A bundle that declares an app icon, as the staged app does.
    private func bundleDeclaringAnIcon() throws -> (bundle: Bundle, root: URL) {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "movingpaper-icon-\(UUID().uuidString).bundle")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let info: [String: Any] = ["CFBundleIdentifier": "test.movingpaper.icon", "CFBundleIconName": "MovingPaper"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: root.appending(path: "Info.plist"))
        return (try #require(Bundle(url: root)), root)
    }

    @Test func aBundledAppShowsItsOwnIconInColour() throws {
        let (bundle, root) = try bundleDeclaringAnIcon()
        defer { try? FileManager.default.removeItem(at: root) }

        let icon = MenuBarIcon.brandIcon(bundle: bundle)
        #expect(!icon.isTemplate)
        #expect(icon.size == MenuBarIcon.pointSize)
        #expect(icon.size.width == icon.size.height)
        #expect(icon.accessibilityDescription == "MovingPaper")
        #expect(!icon.representations.isEmpty)
    }

    /// The shared app-icon image must stay untouched: resizing it in place would
    /// shrink the icon everywhere else it is drawn, such as in alerts.
    @Test func theSharedAppIconIsNotResized() throws {
        let (bundle, root) = try bundleDeclaringAnIcon()
        defer { try? FileManager.default.removeItem(at: root) }
        let shared = try #require(NSImage(named: NSImage.applicationIconName))
        let before = shared.size

        _ = MenuBarIcon.brandIcon(bundle: bundle)
        #expect(shared.size == before)
    }

    /// `swift run` and the test runner have no icon of their own.
    @Test func anUnbundledRunFallsBackToATemplateSymbol() throws {
        let symbol = try #require(NSImage(systemSymbolName: "cloud.moon.fill", accessibilityDescription: nil))
        let icon = MenuBarIcon.brandIcon(bundle: Bundle(for: BundleAnchor.self))
        #expect(icon.isTemplate)
        #expect(icon.size == symbol.size)
        #expect(icon.accessibilityDescription == "MovingPaper")
    }
}

private final class BundleAnchor {}
