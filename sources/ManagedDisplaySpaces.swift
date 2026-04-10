import AppKit
import CoreGraphics
import Foundation

@_silgen_name("CGSMainConnectionID")
private func CGSMainConnectionID() -> UInt32

@_silgen_name("CGSGetActiveSpace")
private func CGSGetActiveSpace(_: UInt32) -> UInt64

@_silgen_name("CGSCopyManagedDisplaySpaces")
private func CGSCopyManagedDisplaySpaces(_: UInt32) -> CFArray

/// Snapshot of the current active and known Spaces for each connected display.
struct ManagedDisplaySpacesSnapshot: Equatable {
    let activeSpaceByDisplayID: [CGDirectDisplayID: UInt64]
    let knownSpacesByDisplayID: [CGDirectDisplayID: Set<UInt64>]

    static func current(screens: [NSScreen] = NSScreen.screens) -> ManagedDisplaySpacesSnapshot {
        let rawEntries = (CGSCopyManagedDisplaySpaces(CGSMainConnectionID()) as? [[String: Any]]) ?? []
        return from(
            rawEntries: rawEntries,
            screensByDisplayIdentifier: displayIdentifiers(for: screens),
            fallbackGlobalSpaceID: currentGlobalSpaceID()
        )
    }

    static func from(
        rawEntries: [[String: Any]],
        screensByDisplayIdentifier: [String: CGDirectDisplayID],
        fallbackGlobalSpaceID: UInt64
    ) -> ManagedDisplaySpacesSnapshot {
        var activeSpaceByDisplayID = Dictionary(
            uniqueKeysWithValues: screensByDisplayIdentifier.values.map { ($0, fallbackGlobalSpaceID) }
        )
        var knownSpacesByDisplayID = Dictionary(
            uniqueKeysWithValues: screensByDisplayIdentifier.values.map { ($0, Set<UInt64>()) }
        )

        for entry in rawEntries {
            guard
                let displayIdentifier = entry["Display Identifier"] as? String,
                let displayID = screensByDisplayIdentifier[displayIdentifier],
                let currentSpace = spaceID(from: entry["Current Space"])
            else {
                continue
            }

            activeSpaceByDisplayID[displayID] = currentSpace

            var knownSpaces = knownSpacesByDisplayID[displayID] ?? []
            knownSpaces.insert(currentSpace)

            if let spaces = entry["Spaces"] as? [Any] {
                for space in spaces {
                    if let parsedSpaceID = spaceID(from: space) {
                        knownSpaces.insert(parsedSpaceID)
                    }
                }
            }

            knownSpacesByDisplayID[displayID] = knownSpaces
        }

        for displayID in screensByDisplayIdentifier.values where knownSpacesByDisplayID[displayID]?.isEmpty != false {
            knownSpacesByDisplayID[displayID] = [fallbackGlobalSpaceID]
        }

        return ManagedDisplaySpacesSnapshot(
            activeSpaceByDisplayID: activeSpaceByDisplayID,
            knownSpacesByDisplayID: knownSpacesByDisplayID
        )
    }

    private static func displayIdentifiers(for screens: [NSScreen]) -> [String: CGDirectDisplayID] {
        Dictionary(
            uniqueKeysWithValues: screens.compactMap { screen in
                guard
                    let displayID = screen.displayID,
                    let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue()
                else {
                    return nil
                }

                let identifier = CFUUIDCreateString(nil, uuid) as String
                return (identifier, displayID)
            }
        )
    }

    private static func spaceID(from value: Any?) -> UInt64? {
        guard let dictionary = value as? [String: Any] else { return nil }
        if let id = dictionary["id64"] as? NSNumber {
            return id.uint64Value
        }
        if let id = dictionary["id64"] as? UInt64 {
            return id
        }
        if let id = dictionary["id64"] as? Int {
            return UInt64(id)
        }
        return nil
    }
}

func currentGlobalSpaceID() -> UInt64 {
    CGSGetActiveSpace(CGSMainConnectionID())
}
