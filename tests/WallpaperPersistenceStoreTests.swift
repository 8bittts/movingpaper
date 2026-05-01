import CoreGraphics
import Foundation
import Testing
@testable import MovingPaper

struct WallpaperPersistenceStoreTests {

    @Test func savesAndLoadsExistingAssignments() throws {
        let defaults = try temporaryDefaults()
        defer { defaults.cleanup() }

        let wallpaperURL = defaults.directory.appendingPathComponent("wallpaper.mp4")
        FileManager.default.createFile(atPath: wallpaperURL.path(percentEncoded: false), contents: Data())

        let key = DesktopKey(displayID: 99, spaceID: 42)
        let store = WallpaperPersistenceStore(userDefaults: defaults.userDefaults)

        store.save(
            mode: .perDesktop,
            isMuted: false,
            desktopFiles: [key: wallpaperURL],
            youtubeURLs: [key: "https://www.youtube.com/watch?v=dQw4w9WgXcQ"]
        )

        let loaded = store.load()
        #expect(loaded.mode == .perDesktop)
        #expect(loaded.isMuted == false)
        #expect(loaded.desktopFiles == [key: wallpaperURL])
        #expect(loaded.youtubeURLs == [key: "https://www.youtube.com/watch?v=dQw4w9WgXcQ"])
        #expect(loaded.knownSpaces[99] == Set([42]))
        #expect(loaded.needsRedownload.isEmpty)
    }

    @Test func queuesMissingYouTubeBackedFilesForRedownload() throws {
        let defaults = try temporaryDefaults()
        defer { defaults.cleanup() }

        let missingPath = defaults.directory.appendingPathComponent("missing.mp4").path(percentEncoded: false)
        let store = WallpaperPersistenceStore(userDefaults: defaults.userDefaults)
        defaults.userDefaults.set("perDesktop", forKey: "wallpaperMode")
        defaults.userDefaults.set(false, forKey: "isMuted")
        defaults.userDefaults.set(
            [
                [
                    "displayID": NSNumber(value: CGDirectDisplayID(7)),
                    "spaceID": NSNumber(value: UInt64(3)),
                    "path": missingPath,
                    "youtubeURL": "https://youtu.be/dQw4w9WgXcQ",
                ],
            ],
            forKey: "desktopFiles"
        )

        let loaded = store.load()
        let key = DesktopKey(displayID: 7, spaceID: 3)
        #expect(loaded.desktopFiles.isEmpty)
        #expect(loaded.youtubeURLs == [key: "https://youtu.be/dQw4w9WgXcQ"])
        #expect(loaded.knownSpaces[7] == Set([3]))
        #expect(loaded.needsRedownload == [
            WallpaperRedownloadRequest(key: key, youtubeURL: "https://youtu.be/dQw4w9WgXcQ"),
        ])
    }

    @Test func defaultsMissingModeAndMuteToCurrentBehavior() throws {
        let defaults = try temporaryDefaults()
        defer { defaults.cleanup() }

        let loaded = WallpaperPersistenceStore(userDefaults: defaults.userDefaults).load()
        #expect(loaded.mode == .allDesktops)
        #expect(loaded.isMuted)
        #expect(loaded.desktopFiles.isEmpty)
        #expect(loaded.youtubeURLs.isEmpty)
        #expect(loaded.knownSpaces.isEmpty)
        #expect(loaded.needsRedownload.isEmpty)
    }

    private func temporaryDefaults() throws -> TemporaryDefaults {
        let suiteName = "MovingPaperTests.\(UUID().uuidString)"
        guard let userDefaults = UserDefaults(suiteName: suiteName) else {
            throw TemporaryDefaultsError.unavailable
        }
        userDefaults.removePersistentDomain(forName: suiteName)

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MovingPaperTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        return TemporaryDefaults(suiteName: suiteName, userDefaults: userDefaults, directory: directory)
    }
}

private struct TemporaryDefaults {
    let suiteName: String
    let userDefaults: UserDefaults
    let directory: URL

    func cleanup() {
        userDefaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
    }
}

private enum TemporaryDefaultsError: Error {
    case unavailable
}
