import CoreGraphics
import Foundation

struct WallpaperRedownloadRequest: Equatable {
    let key: DesktopKey
    let youtubeURL: String
    /// The persisted cache path this YouTube video should occupy once redownloaded.
    /// Kept so an in-flight request can be re-persisted verbatim across saves.
    let localURL: URL
}

struct WallpaperPersistedState: Equatable {
    var mode: WallpaperMode
    var isMuted: Bool
    var state: WallpaperState
    var needsRedownload: [WallpaperRedownloadRequest]

    static let empty = WallpaperPersistedState(
        mode: .allDesktops,
        isMuted: true,
        state: WallpaperState(),
        needsRedownload: []
    )
}

struct WallpaperPersistenceStore {
    private enum Defaults {
        static let desktopFiles = "desktopFiles"
        static let mode = "wallpaperMode"
        static let isMuted = "isMuted"
        static let schemaVersion = "persistenceSchemaVersion"
    }

    /// Bump this when the on-disk schema for any of the persisted keys changes,
    /// and add a migration step in `runMigrationsIfNeeded`.
    static let currentSchemaVersion = 1

    private let userDefaults: UserDefaults
    private let fileExists: (String) -> Bool

    init(
        userDefaults: UserDefaults = .standard,
        fileExists: @escaping (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) {
        self.userDefaults = userDefaults
        self.fileExists = fileExists
    }

    /// Runs any pending schema migrations and stamps the current version. Safe
    /// to call repeatedly; older versions become newer in place.
    private func runMigrationsIfNeeded() {
        // `integer(forKey:)` returns 0 when the key is absent, which is exactly
        // what we want for pre-versioned defaults — those store the v1 shape.
        let saved = userDefaults.integer(forKey: Defaults.schemaVersion)
        guard saved < Self.currentSchemaVersion else { return }

        // Future migrations slot in here, ordered from low version to high.
        // e.g. `if saved < 2 { migrateToV2() }`

        userDefaults.set(Self.currentSchemaVersion, forKey: Defaults.schemaVersion)
    }

    func save(
        mode: WallpaperMode,
        isMuted: Bool,
        state: WallpaperState,
        pendingRedownloads: [WallpaperRedownloadRequest] = []
    ) {
        var encoded: [[String: Any]] = state.entries.map { key, entry in
            var record: [String: Any] = [
                "displayID": NSNumber(value: key.displayID),
                "spaceID": NSNumber(value: key.spaceID),
                "path": entry.localURL.path(percentEncoded: false),
            ]
            if let youtubeURL = entry.youtubeOrigin {
                record["youtubeURL"] = youtubeURL
            }
            return record
        }

        // Re-emit still-pending YouTube redownloads (cache file missing, not yet
        // resolved) so an unrelated save during the redownload window doesn't
        // erase them. Skip any key the user has since assigned directly.
        for request in pendingRedownloads where state.entries[request.key] == nil {
            encoded.append([
                "displayID": NSNumber(value: request.key.displayID),
                "spaceID": NSNumber(value: request.key.spaceID),
                "path": request.localURL.path(percentEncoded: false),
                "youtubeURL": request.youtubeURL,
            ])
        }

        userDefaults.set(encoded, forKey: Defaults.desktopFiles)
        userDefaults.set(mode.rawValue, forKey: Defaults.mode)
        userDefaults.set(isMuted, forKey: Defaults.isMuted)
    }

    func load() -> WallpaperPersistedState {
        runMigrationsIfNeeded()
        var persisted = WallpaperPersistedState.empty

        if let raw = userDefaults.string(forKey: Defaults.mode),
           let savedMode = WallpaperMode(rawValue: raw) {
            persisted.mode = savedMode
        }
        persisted.isMuted = userDefaults.object(forKey: Defaults.isMuted) as? Bool ?? true

        guard let records = userDefaults.array(forKey: Defaults.desktopFiles) as? [[String: Any]] else {
            return persisted
        }

        for record in records {
            guard
                let displayIDNum = record["displayID"] as? NSNumber,
                let spaceIDNum = record["spaceID"] as? NSNumber,
                let path = record["path"] as? String
            else {
                continue
            }

            let key = DesktopKey(
                displayID: displayIDNum.uint32Value,
                spaceID: spaceIDNum.uint64Value
            )
            let youtubeURL = record["youtubeURL"] as? String

            if key.spaceID != 0 {
                persisted.state.knownSpaces[key.displayID, default: []].insert(key.spaceID)
            }

            if fileExists(path) {
                persisted.state.entries[key] = WallpaperEntry(
                    localURL: URL(filePath: path),
                    youtubeOrigin: youtubeURL
                )
            } else if let youtubeURL {
                persisted.needsRedownload.append(
                    WallpaperRedownloadRequest(key: key, youtubeURL: youtubeURL, localURL: URL(filePath: path))
                )
            }
        }

        return persisted
    }
}
