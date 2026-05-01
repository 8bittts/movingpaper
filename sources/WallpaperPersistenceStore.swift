import CoreGraphics
import Foundation

struct WallpaperRedownloadRequest: Equatable {
    let key: DesktopKey
    let youtubeURL: String
}

struct WallpaperPersistedState: Equatable {
    var mode: WallpaperMode
    var isMuted: Bool
    var desktopFiles: [DesktopKey: URL]
    var youtubeURLs: [DesktopKey: String]
    var knownSpaces: [CGDirectDisplayID: Set<UInt64>]
    var needsRedownload: [WallpaperRedownloadRequest]

    static let empty = WallpaperPersistedState(
        mode: .allDesktops,
        isMuted: true,
        desktopFiles: [:],
        youtubeURLs: [:],
        knownSpaces: [:],
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

    func save(mode: WallpaperMode, isMuted: Bool, desktopFiles: [DesktopKey: URL], youtubeURLs: [DesktopKey: String]) {
        let encoded: [[String: Any]] = desktopFiles.map { key, url in
            var entry: [String: Any] = [
                "displayID": NSNumber(value: key.displayID),
                "spaceID": NSNumber(value: key.spaceID),
                "path": url.path(percentEncoded: false),
            ]
            if let youtubeURL = youtubeURLs[key] {
                entry["youtubeURL"] = youtubeURL
            }
            return entry
        }

        userDefaults.set(encoded, forKey: Defaults.desktopFiles)
        userDefaults.set(mode.rawValue, forKey: Defaults.mode)
        userDefaults.set(isMuted, forKey: Defaults.isMuted)
    }

    func load() -> WallpaperPersistedState {
        var state = WallpaperPersistedState.empty

        if let raw = userDefaults.string(forKey: Defaults.mode),
           let savedMode = WallpaperMode(rawValue: raw) {
            state.mode = savedMode
        }
        state.isMuted = userDefaults.object(forKey: Defaults.isMuted) as? Bool ?? true

        guard let entries = userDefaults.array(forKey: Defaults.desktopFiles) as? [[String: Any]] else {
            return state
        }

        for entry in entries {
            guard
                let displayIDNum = entry["displayID"] as? NSNumber,
                let spaceIDNum = entry["spaceID"] as? NSNumber,
                let path = entry["path"] as? String
            else {
                continue
            }

            let key = DesktopKey(
                displayID: displayIDNum.uint32Value,
                spaceID: spaceIDNum.uint64Value
            )

            if let youtubeURL = entry["youtubeURL"] as? String {
                state.youtubeURLs[key] = youtubeURL
            }

            if key.spaceID != 0 {
                state.knownSpaces[key.displayID, default: []].insert(key.spaceID)
            }

            if fileExists(path) {
                state.desktopFiles[key] = URL(filePath: path)
            } else if let youtubeURL = entry["youtubeURL"] as? String {
                state.needsRedownload.append(WallpaperRedownloadRequest(key: key, youtubeURL: youtubeURL))
            }
        }

        return state
    }
}
