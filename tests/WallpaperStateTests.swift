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

    @Test func setEntryIgnoresTheAllDesktopsSentinelSpace() {
        var state = WallpaperState()
        // DesktopKey(displayID:) uses spaceID 0, the all-desktops sentinel.
        let key = DesktopKey(displayID: displayA)
        state.setEntry(WallpaperEntry(localURL: localURL, youtubeOrigin: nil), for: key)
        #expect(state.entries[key]?.localURL == localURL)
        // spaceID 0 must not be recorded as a known Space, or a phantom "Desktop 1"
        // row appears in the Per Desktop menu after an all-desktops assignment.
        #expect(state.knownSpaces[displayA] == nil)
    }

    @Test func canonicalEntryIsDeterministicByDisplayThenSpace() {
        let entryLow = WallpaperEntry(localURL: URL(filePath: "/low.mp4"), youtubeOrigin: nil)
        let entryHigh = WallpaperEntry(localURL: URL(filePath: "/high.mp4"), youtubeOrigin: nil)

        // Insert in "high then low" order; canonical must still pick the lowest key.
        var state = WallpaperState()
        state.setEntry(entryHigh, for: DesktopKey(displayID: displayB, spaceID: 5))
        state.setEntry(entryLow, for: DesktopKey(displayID: displayA, spaceID: 9))
        #expect(state.canonicalEntry == entryLow)

        // Same display, tie broken by the lower spaceID.
        var tie = WallpaperState()
        tie.setEntry(entryHigh, for: DesktopKey(displayID: displayA, spaceID: 20))
        tie.setEntry(entryLow, for: DesktopKey(displayID: displayA, spaceID: 3))
        #expect(tie.canonicalEntry == entryLow)

        #expect(WallpaperState().canonicalEntry == nil)
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

    @Test func adoptPreservesLiveKnownSpacesAcrossPersistedRestore() {
        // Simulate `refreshManagedDisplaySpaces()` populating fresh Spaces…
        var state = WallpaperState()
        state.knownSpaces[displayA] = Set([7, 8, 9])

        // …then `restoreState()` loading older persistence with different
        // Spaces and assignments. The fresh Spaces must survive the adopt so
        // the Per Desktop menu still shows desktops the user can switch to.
        var persisted = WallpaperState()
        persisted.entries[DesktopKey(displayID: displayA, spaceID: 7)] =
            WallpaperEntry(localURL: localURL, youtubeOrigin: nil)
        persisted.knownSpaces[displayA] = Set([7])
        persisted.knownSpaces[displayB] = Set([42])

        state.adopt(persisted: persisted)

        #expect(state.entries[DesktopKey(displayID: displayA, spaceID: 7)] != nil)
        #expect(state.knownSpaces[displayA] == Set([7, 8, 9]))
        #expect(state.knownSpaces[displayB] == Set([42]))
    }

    @Test func assignAllDesktopsPinsTheEntryOnEveryConnectedDisplay() {
        var state = WallpaperState()
        let entry = WallpaperEntry(localURL: localURL, youtubeOrigin: "https://yt")
        let keys = state.assign(
            entry,
            mode: .allDesktops,
            displayID: displayA,
            spaceID: 9,
            connectedDisplayIDs: [displayA, displayB],
            currentSpaceID: { _ in 99 }
        )

        #expect(Set(keys) == [
            DesktopKey(displayID: displayA),
            DesktopKey(displayID: displayB),
        ])
        #expect(state.entries[DesktopKey(displayID: displayA)] == entry)
        #expect(state.entries[DesktopKey(displayID: displayB)] == entry)
        #expect(state.knownSpaces.isEmpty)
    }

    @Test func assignPerDesktopUsesTheGivenDisplayAndSpace() {
        var state = WallpaperState()
        let entry = WallpaperEntry(localURL: localURL, youtubeOrigin: nil)
        let keys = state.assign(
            entry,
            mode: .perDesktop,
            displayID: displayA,
            spaceID: 7,
            connectedDisplayIDs: [displayA, displayB],
            currentSpaceID: { _ in 99 }
        )

        #expect(keys == [DesktopKey(displayID: displayA, spaceID: 7)])
        #expect(state.entries[DesktopKey(displayID: displayA, spaceID: 7)] == entry)
        #expect(state.entries[DesktopKey(displayID: displayB, spaceID: 99)] == nil)
        #expect(state.knownSpaces[displayA] == Set([7]))
    }

    @Test func assignPerDesktopFallsBackToTheCurrentSpaceWhenSpaceIDIsOmitted() {
        var state = WallpaperState()
        let entry = WallpaperEntry(localURL: localURL, youtubeOrigin: nil)
        let keys = state.assign(
            entry,
            mode: .perDesktop,
            displayID: displayA,
            spaceID: nil,
            connectedDisplayIDs: [displayA],
            currentSpaceID: { _ in 15 }
        )

        #expect(keys == [DesktopKey(displayID: displayA, spaceID: 15)])
        #expect(state.entries[DesktopKey(displayID: displayA, spaceID: 15)] == entry)
    }

    @Test func assignPerDesktopForAllAppliesEveryConnectedDisplayCurrentSpace() {
        var state = WallpaperState()
        let entry = WallpaperEntry(localURL: localURL, youtubeOrigin: nil)
        let keys = state.assign(
            entry,
            mode: .perDesktop,
            displayID: nil,
            spaceID: 0,
            connectedDisplayIDs: [displayA, displayB],
            currentSpaceID: { $0 == displayA ? 100 : 200 }
        )

        #expect(Set(keys) == [
            DesktopKey(displayID: displayA, spaceID: 100),
            DesktopKey(displayID: displayB, spaceID: 200),
        ])
        #expect(state.entries[DesktopKey(displayID: displayA, spaceID: 100)] == entry)
        #expect(state.entries[DesktopKey(displayID: displayB, spaceID: 200)] == entry)
        #expect(state.entries[DesktopKey(displayID: displayA)] == nil)
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
