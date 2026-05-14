import CoreGraphics
import Foundation

struct WallpaperRedownloadRequest: Equatable {
    let key: DesktopKey
    let youtubeURL: String
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
    }

    private let userDefaults: UserDefaults
    private let fileExists: (String) -> Bool

    init(
        userDefaults: UserDefaults = .standard,
        fileExists: @escaping (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) {
        self.userDefaults = userDefaults
        self.fileExists = fileExists
    }

    func save(mode: WallpaperMode, isMuted: Bool, state: WallpaperState) {
        let encoded: [[String: Any]] = state.entries.map { key, entry in
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

        userDefaults.set(encoded, forKey: Defaults.desktopFiles)
        userDefaults.set(mode.rawValue, forKey: Defaults.mode)
        userDefaults.set(isMuted, forKey: Defaults.isMuted)
    }

    func load() -> WallpaperPersistedState {
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
                persisted.needsRedownload.append(WallpaperRedownloadRequest(key: key, youtubeURL: youtubeURL))
            }
        }

        return persisted
    }
}
