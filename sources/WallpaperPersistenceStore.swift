import CoreGraphics
import Foundation

struct WallpaperRedownloadRequest: Equatable {
    let key: DesktopKey
    let youtubeURL: String
    /// The persisted cache path this YouTube video should occupy once redownloaded.
    /// Kept so an in-flight request can be re-persisted verbatim across saves.
    let localURL: URL
}

/// One on-disk wallpaper record. Schema v1 keys are `displayID`, `spaceID`,
/// `path` and optional `youtubeURL`; v2 adds optional `displayUUID`, which
/// survives a restart where `displayID` may not. Keys must stay stable unless
/// `currentSchemaVersion` bumps. `displayID` is still written, so an older build
/// can read a v2 record.
struct WallpaperPersistedRecord: Equatable {
    var displayID: CGDirectDisplayID
    var spaceID: UInt64
    var path: String
    var youtubeURL: String?
    var displayUUID: String?

    init(key: DesktopKey, path: String, youtubeURL: String?, displayUUID: String? = nil) {
        self.displayID = key.displayID
        self.spaceID = key.spaceID
        self.path = path
        self.youtubeURL = youtubeURL
        self.displayUUID = displayUUID
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
        self.displayUUID = plistObject["displayUUID"] as? String
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
        if let displayUUID {
            record["displayUUID"] = displayUUID
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
    static let currentSchemaVersion = 2

    private let userDefaults: UserDefaults
    private let fileExists: (String) -> Bool
    private let displayIdentity: DisplayIdentity

    init(
        userDefaults: UserDefaults = .standard,
        fileExists: @escaping (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        displayIdentity: DisplayIdentity = .system
    ) {
        self.userDefaults = userDefaults
        self.fileExists = fileExists
        self.displayIdentity = displayIdentity
    }

    private func record(key: DesktopKey, path: URL, youtubeURL: String?) -> [String: Any] {
        WallpaperPersistedRecord(
            key: key,
            path: path.path(percentEncoded: false),
            youtubeURL: youtubeURL,
            displayUUID: displayIdentity.uuid(key.displayID)
        ).plistObject()
    }

    /// The record's key on this boot: its display UUID mapped to the display's
    /// current ID when that display is connected, else the saved ID.
    private func currentKey(for record: WallpaperPersistedRecord) -> DesktopKey {
        guard let uuid = record.displayUUID,
              let displayID = displayIdentity.connectedDisplayID(uuid)
        else { return record.key }
        return DesktopKey(displayID: displayID, spaceID: record.spaceID)
    }

    /// Runs any pending schema migrations and stamps the current version. Safe
    /// to call repeatedly; older versions become newer in place.
    private func runMigrationsIfNeeded() {
        // `integer(forKey:)` returns 0 when the key is absent, which is exactly
        // what we want for pre-versioned defaults — those store the v1 shape.
        let saved = userDefaults.integer(forKey: Defaults.schemaVersion)
        guard saved < Self.currentSchemaVersion else { return }

        // Migrations run in order, from low version to high.
        // v1 → v2: v1 records carry no `displayUUID`. They need no rewrite: `load`
        // keys a record without one by its saved `displayID`, and the next save
        // adds the UUID.

        userDefaults.set(Self.currentSchemaVersion, forKey: Defaults.schemaVersion)
    }

    func save(
        mode: WallpaperMode,
        isMuted: Bool,
        state: WallpaperState,
        pendingRedownloads: [WallpaperRedownloadRequest] = []
    ) {
        var encoded: [[String: Any]] = state.entries.map { key, entry in
            record(key: key, path: entry.localURL, youtubeURL: entry.youtubeOrigin)
        }

        // Re-emit still-pending YouTube redownloads (cache file missing, not yet
        // resolved) so an unrelated save during the redownload window doesn't
        // erase them. Skip any key the user has since assigned directly.
        for request in pendingRedownloads where state.entries[request.key] == nil {
            encoded.append(record(key: request.key, path: request.localURL, youtubeURL: request.youtubeURL))
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

            let key = currentKey(for: parsed)
            if !key.isAllDesktops {
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
