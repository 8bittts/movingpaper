import CoreGraphics
import CoreMedia
import Foundation

/// A single per-desktop wallpaper assignment. The optional `youtubeOrigin` is
/// retained so persistence can re-download a missing local file on next launch.
struct WallpaperEntry: Equatable {
    var localURL: URL
    var youtubeOrigin: String?
}

/// All in-memory wallpaper state. Replaces the previous parallel dictionaries
/// (`desktopFiles`, `youtubeURLs`, `playbackPositions`, `knownSpaces`) so that
/// every mutation touches one canonical store.
struct WallpaperState: Equatable {
    var entries: [DesktopKey: WallpaperEntry] = [:]
    var playbackPositions: [DesktopKey: CMTime] = [:]
    /// Every Space we've ever observed on each display. macOS exposes no API to
    /// enumerate Spaces, so we accumulate them as the user visits.
    var knownSpaces: [CGDirectDisplayID: Set<UInt64>] = [:]

    var isEmpty: Bool { entries.isEmpty }

    func localURL(for key: DesktopKey) -> URL? { entries[key]?.localURL }

    /// The single shared URL when all desktops share one wallpaper, or `nil`.
    var sharedLocalURL: URL? { entries.values.first?.localURL }

    mutating func setEntry(_ entry: WallpaperEntry, for key: DesktopKey) {
        entries[key] = entry
        knownSpaces[key.displayID, default: []].insert(key.spaceID)
    }

    mutating func clearEntry(for key: DesktopKey) {
        entries.removeValue(forKey: key)
        playbackPositions.removeValue(forKey: key)
    }

    /// Replace all assignments with a single shared entry across the given displays.
    /// Used when switching to `.allDesktops` mode or when the wallpaper changes globally.
    mutating func applyShared(entry: WallpaperEntry, across displayIDs: [CGDirectDisplayID]) {
        entries.removeAll()
        for id in displayIDs {
            entries[DesktopKey(displayID: id)] = entry
        }
    }

    /// Replace this state's entries and playback positions with `persisted`'s,
    /// but keep every Space we already saw from the live system snapshot.
    /// Used after `refreshManagedDisplaySpaces()` so loading persistence does
    /// not erase Spaces the user can currently switch to — those would never
    /// appear in the Per Desktop menu otherwise.
    mutating func adopt(persisted: WallpaperState) {
        let liveKnownSpaces = knownSpaces
        self = persisted
        for (displayID, spaces) in liveKnownSpaces {
            knownSpaces[displayID, default: []].formUnion(spaces)
        }
    }

    /// Drop assignments for displays not in `connectedDisplayIDs` and pin the
    /// shared value (if any) to every connected display. Mirrors
    /// `AllDesktopAssignmentReconciler` but operates on full entries.
    @discardableResult
    mutating func reconcileAllDesktops(connectedDisplayIDs: [CGDirectDisplayID]) -> Bool {
        guard let shared = entries.values.first else { return false }
        let expected = Set(connectedDisplayIDs.map(DesktopKey.init(displayID:)))
        var changed = false

        for key in Array(entries.keys) where !expected.contains(key) {
            entries.removeValue(forKey: key)
            changed = true
        }

        for id in connectedDisplayIDs {
            let key = DesktopKey(displayID: id)
            if entries[key] != shared {
                entries[key] = shared
                changed = true
            }
        }

        return changed
    }

    /// Re-key existing assignments to (display, currentSpace) so per-desktop
    /// switching from `.allDesktops` preserves the wallpaper on the active Space.
    mutating func migrateToPerDesktop(currentSpace: (CGDirectDisplayID) -> UInt64) {
        let snapshot = entries
        entries.removeAll()
        for (oldKey, entry) in snapshot {
            let space = currentSpace(oldKey.displayID)
            let newKey = DesktopKey(displayID: oldKey.displayID, spaceID: space)
            entries[newKey] = entry
            knownSpaces[oldKey.displayID, default: []].insert(space)
        }
    }
}
