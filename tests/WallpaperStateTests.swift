import CoreGraphics
import Foundation
import Testing
@testable import MovingPaper

struct WallpaperStateTests {

    private let displayA: CGDirectDisplayID = 11
    private let displayB: CGDirectDisplayID = 22
    private let localURL = URL(filePath: "/tmp/movingpaper-state-tests/wallpaper.mp4")

    @Test func setEntryRecordsTheVisitedSpace() {
        var state = WallpaperState()
        let key = DesktopKey(displayID: displayA, spaceID: 5)
        state.setEntry(WallpaperEntry(localURL: localURL, youtubeOrigin: nil), for: key)
        #expect(state.entries[key]?.localURL == localURL)
        #expect(state.knownSpaces[displayA] == Set([5]))
    }

    @Test func clearEntryRemovesEntryAndPlaybackPosition() {
        var state = WallpaperState()
        let key = DesktopKey(displayID: displayA, spaceID: 5)
        state.setEntry(WallpaperEntry(localURL: localURL, youtubeOrigin: nil), for: key)
        state.playbackPositions[key] = .zero

        state.clearEntry(for: key)

        #expect(state.entries[key] == nil)
        #expect(state.playbackPositions[key] == nil)
        // knownSpaces is intentionally NOT pruned — we still want to show the
        // Space in the menu even after the user removes its wallpaper.
        #expect(state.knownSpaces[displayA] == Set([5]))
    }

    @Test func applySharedClearsExistingEntriesAndPinsToEveryDisplay() {
        var state = WallpaperState()
        state.setEntry(
            WallpaperEntry(localURL: URL(filePath: "/tmp/old.mp4"), youtubeOrigin: nil),
            for: DesktopKey(displayID: displayA, spaceID: 9)
        )

        state.applyShared(
            entry: WallpaperEntry(localURL: localURL, youtubeOrigin: "https://yt"),
            across: [displayA, displayB]
        )

        #expect(state.entries.count == 2)
        #expect(state.entries[DesktopKey(displayID: displayA)]?.localURL == localURL)
        #expect(state.entries[DesktopKey(displayID: displayB)]?.youtubeOrigin == "https://yt")
    }

    @Test func reconcileAllDesktopsAddsMissingDisplaysAndDropsDisconnected() {
        var state = WallpaperState()
        let entry = WallpaperEntry(localURL: localURL, youtubeOrigin: nil)
        state.entries[DesktopKey(displayID: displayA)] = entry

        let didChange = state.reconcileAllDesktops(connectedDisplayIDs: [displayA, displayB])
        #expect(didChange == true)
        #expect(state.entries[DesktopKey(displayID: displayB)] == entry)

        let didChangeAgain = state.reconcileAllDesktops(connectedDisplayIDs: [displayB])
        #expect(didChangeAgain == true)
        #expect(state.entries[DesktopKey(displayID: displayA)] == nil)
        #expect(state.entries[DesktopKey(displayID: displayB)] == entry)
    }

    @Test func reconcileAllDesktopsIsNoopWhenStateIsEmpty() {
        var state = WallpaperState()
        let didChange = state.reconcileAllDesktops(connectedDisplayIDs: [displayA])
        #expect(didChange == false)
        #expect(state.entries.isEmpty)
    }

    @Test func migrateToPerDesktopRekeysExistingAssignmentsToTheActiveSpace() {
        var state = WallpaperState()
        let entry = WallpaperEntry(localURL: localURL, youtubeOrigin: nil)
        state.entries[DesktopKey(displayID: displayA)] = entry
        state.entries[DesktopKey(displayID: displayB)] = entry

        state.migrateToPerDesktop { displayID in
            displayID == displayA ? 100 : 200
        }

        #expect(state.entries[DesktopKey(displayID: displayA)] == nil)
        #expect(state.entries[DesktopKey(displayID: displayA, spaceID: 100)] == entry)
        #expect(state.entries[DesktopKey(displayID: displayB, spaceID: 200)] == entry)
        #expect(state.knownSpaces[displayA] == Set([100]))
        #expect(state.knownSpaces[displayB] == Set([200]))
    }
}
