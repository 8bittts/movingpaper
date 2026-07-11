import CoreGraphics
import Foundation
import Testing
@testable import MovingPaper

struct ManagedDisplaySpacesSnapshotTests {

    @Test func parsesPerDisplayCurrentAndKnownSpaces() {
        let snapshot = ManagedDisplaySpacesSnapshot.from(
            rawEntries: [
                [
                    "Display Identifier": "DISPLAY-A",
                    "Current Space": ["id64": NSNumber(value: 7)],
                    "Spaces": [
                        ["id64": NSNumber(value: 3)],
                        ["id64": NSNumber(value: 7)],
                        ["id64": NSNumber(value: 11)],
                    ],
                ],
                [
                    "Display Identifier": "DISPLAY-B",
                    "Current Space": ["id64": NSNumber(value: 19)],
                    "Spaces": [
                        ["id64": NSNumber(value: 19)],
                    ],
                ],
            ],
            screensByDisplayIdentifier: [
                "DISPLAY-A": CGDirectDisplayID(101),
                "DISPLAY-B": CGDirectDisplayID(202),
            ],
            fallbackGlobalSpaceID: 1
        )

        #expect(snapshot.activeSpaceByDisplayID[CGDirectDisplayID(101)] == 7)
        #expect(snapshot.activeSpaceByDisplayID[CGDirectDisplayID(202)] == 19)
        #expect(snapshot.knownSpacesByDisplayID[CGDirectDisplayID(101)] == Set([3, 7, 11]))
        #expect(snapshot.knownSpacesByDisplayID[CGDirectDisplayID(202)] == Set([19]))
    }

    @Test func ignoresEntriesForDisplaysNotCurrentlyConnected() {
        let snapshot = ManagedDisplaySpacesSnapshot.from(
            rawEntries: [
                [
                    // Stale entry for a display that is no longer connected.
                    "Display Identifier": "DISPLAY-GHOST",
                    "Current Space": ["id64": NSNumber(value: 500)],
                    "Spaces": [["id64": NSNumber(value: 500)]],
                ],
                [
                    "Display Identifier": "DISPLAY-A",
                    "Current Space": ["id64": NSNumber(value: 7)],
                    "Spaces": [["id64": NSNumber(value: 7)]],
                ],
            ],
            screensByDisplayIdentifier: ["DISPLAY-A": CGDirectDisplayID(101)],
            fallbackGlobalSpaceID: 1
        )

        #expect(snapshot.activeSpaceByDisplayID.count == 1)
        #expect(snapshot.activeSpaceByDisplayID[CGDirectDisplayID(101)] == 7)
        #expect(snapshot.knownSpacesByDisplayID[CGDirectDisplayID(101)] == Set([7]))
        // The ghost display's space is not tracked against any connected display.
        #expect(!snapshot.knownSpacesByDisplayID.values.contains { $0.contains(500) })
    }

    @Test func recordsCurrentSpaceWhenNoSpacesListIsPresent() {
        let snapshot = ManagedDisplaySpacesSnapshot.from(
            rawEntries: [
                [
                    "Display Identifier": "DISPLAY-A",
                    "Current Space": ["id64": NSNumber(value: 42)],
                    // No "Spaces" key at all.
                ],
            ],
            screensByDisplayIdentifier: ["DISPLAY-A": CGDirectDisplayID(101)],
            fallbackGlobalSpaceID: 1
        )

        #expect(snapshot.activeSpaceByDisplayID[CGDirectDisplayID(101)] == 42)
        #expect(snapshot.knownSpacesByDisplayID[CGDirectDisplayID(101)] == Set([42]))
    }

    @Test func fallsBackWhenEntryHasNoParseableCurrentSpace() {
        let snapshot = ManagedDisplaySpacesSnapshot.from(
            rawEntries: [
                [
                    "Display Identifier": "DISPLAY-A",
                    // "Current Space" missing → the whole entry is skipped.
                    "Spaces": [["id64": NSNumber(value: 3)]],
                ],
            ],
            screensByDisplayIdentifier: ["DISPLAY-A": CGDirectDisplayID(101)],
            fallbackGlobalSpaceID: 9
        )

        #expect(snapshot.activeSpaceByDisplayID[CGDirectDisplayID(101)] == 9)
        #expect(snapshot.knownSpacesByDisplayID[CGDirectDisplayID(101)] == Set([9]))
    }

    @Test func fallsBackWhenAConnectedDisplayHasNoManagedSpaceEntry() {
        let snapshot = ManagedDisplaySpacesSnapshot.from(
            rawEntries: [],
            screensByDisplayIdentifier: [
                "DISPLAY-A": CGDirectDisplayID(55),
            ],
            fallbackGlobalSpaceID: 9
        )

        #expect(snapshot.activeSpaceByDisplayID[CGDirectDisplayID(55)] == 9)
        #expect(snapshot.knownSpacesByDisplayID[CGDirectDisplayID(55)] == Set([9]))
    }
}
