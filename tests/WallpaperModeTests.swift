import Testing
import AppKit
import Foundation
@testable import MovingPaper

/// Tests for wallpaper mode logic.
struct WallpaperModeTests {

    @Test func modeRawValues() {
        #expect(WallpaperMode.allDesktops.rawValue == "allDesktops")
        #expect(WallpaperMode.perDesktop.rawValue == "perDesktop")
    }

    @Test func modesAreDistinct() {
        #expect(WallpaperMode.allDesktops != WallpaperMode.perDesktop)
    }
}

/// Tests for NSScreen.displayID extension behavior.
struct DisplayIDTests {

    @Test func screensHaveDisplayIDs() {
        for screen in NSScreen.screens {
            let displayID = screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
            ] as? CGDirectDisplayID
            #expect(displayID != nil)
        }
    }
}
