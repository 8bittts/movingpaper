import CoreGraphics
import Foundation

struct WallpaperRedownloadRequest: Equatable {
    let key: DesktopKey
    let youtubeURL: String
    /// The persisted cache path this YouTube video should occupy once redownloaded.
    /// Kept so an in-flight request can be re-persisted verbatim across saves.
    let localURL: URL
}

/// One on-disk wallpaper record. Keys are schema v1 (`displayID`, `spaceID`,
/// `path`, optional `youtubeURL`) and must stay stable unless `currentSchemaVersion` bumps.
struct WallpaperPersistedRecord: Equatable {
    var displayID: CGDirectDisplayID
    var spaceID: UInt64
    var path: String
    var youtubeURL: String?

    init(key: DesktopKey, path: String, youtubeURL: String?) {
        self.displayID = key.displayID
        self.spaceID = key.spaceID
        self.path = path
        self.youtubeURL = youtubeURL
    }

    init?(plistObject: [String: Any]) {
        guard
            let displayIDNum = plistObject["displayID"] as? NSNumber,
            let spaceIDNum = plistObject["spaceID"] as? NSNumber,
            let path = plistObject["path"] as? String
        else {
            return nil
        }
        self.displayID = displayIDNum.uint32Value
        self.spaceID = spaceIDNum.uint64Value
        self.path = path
        self.youtubeURL = plistObject["youtubeURL"] as? String
    }

    var key: DesktopKey {
        DesktopKey(displayID: displayID, spaceID: spaceID)
    }

    func plistObject() -> [String: Any] {
        var record: [String: Any] = [
            "displayID": NSNumber(value: displayID),
            "spaceID": NSNumber(value: spaceID),
            "path": path,
        ]
        if let youtubeURL {
            record["youtubeURL"] = youtubeURL
        }
        return record
    }
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
            WallpaperPersistedRecord(
                key: key,
                path: entry.localURL.path(percentEncoded: false),
                youtubeURL: entry.youtubeOrigin
            ).plistObject()
        }

        // Re-emit still-pending YouTube redownloads (cache file missing, not yet
        // resolved) so an unrelated save during the redownload window doesn't
        // erase them. Skip any key the user has since assigned directly.
        for request in pendingRedownloads where state.entries[request.key] == nil {
            encoded.append(
                WallpaperPersistedRecord(
                    key: request.key,
                    path: request.localURL.path(percentEncoded: false),
                    youtubeURL: request.youtubeURL
                ).plistObject()
            )
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
            guard let parsed = WallpaperPersistedRecord(plistObject: record) else {
                continue
            }

            let key = parsed.key
            if key.spaceID != 0 {
                persisted.state.knownSpaces[key.displayID, default: []].insert(key.spaceID)
            }

            if fileExists(parsed.path) {
                persisted.state.entries[key] = WallpaperEntry(
                    localURL: URL(filePath: parsed.path),
                    youtubeOrigin: parsed.youtubeURL
                )
            } else if let youtubeURL = parsed.youtubeURL {
                persisted.needsRedownload.append(
                    WallpaperRedownloadRequest(
                        key: key,
                        youtubeURL: youtubeURL,
                        localURL: URL(filePath: parsed.path)
                    )
                )
            }
        }

        return persisted
    }
}
