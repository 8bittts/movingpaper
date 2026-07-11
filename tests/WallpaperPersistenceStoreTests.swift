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

        var state = WallpaperState()
        state.setEntry(
            WallpaperEntry(
                localURL: wallpaperURL,
                youtubeOrigin: "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
            ),
            for: key
        )

        store.save(mode: .perDesktop, isMuted: false, state: state)

        let loaded = store.load()
        #expect(loaded.mode == .perDesktop)
        #expect(loaded.isMuted == false)
        #expect(loaded.state.entries == [
            key: WallpaperEntry(
                localURL: wallpaperURL,
                youtubeOrigin: "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
            )
        ])
        #expect(loaded.state.knownSpaces[99] == Set([42]))
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
        #expect(loaded.state.entries.isEmpty)
        #expect(loaded.state.knownSpaces[7] == Set([3]))
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
        #expect(loaded.state.entries.isEmpty)
        #expect(loaded.state.knownSpaces.isEmpty)
        #expect(loaded.needsRedownload.isEmpty)
    }

    @Test func loadStampsTheCurrentSchemaVersion() throws {
        let defaults = try temporaryDefaults()
        defer { defaults.cleanup() }

        #expect(defaults.userDefaults.integer(forKey: "persistenceSchemaVersion") == 0)
        _ = WallpaperPersistenceStore(userDefaults: defaults.userDefaults).load()
        #expect(
            defaults.userDefaults.integer(forKey: "persistenceSchemaVersion")
                == WallpaperPersistenceStore.currentSchemaVersion
        )
    }

    @Test func dropsMissingLocalFileWithNoYouTubeOrigin() throws {
        let defaults = try temporaryDefaults()
        defer { defaults.cleanup() }

        let missingPath = defaults.directory.appendingPathComponent("gone.mp4").path(percentEncoded: false)
        let store = WallpaperPersistenceStore(userDefaults: defaults.userDefaults)
        defaults.userDefaults.set(
            [[
                "displayID": NSNumber(value: CGDirectDisplayID(5)),
                "spaceID": NSNumber(value: UInt64(9)),
                "path": missingPath,
            ]],
            forKey: "desktopFiles"
        )

        let loaded = store.load()
        // No local file and no youtubeURL → assignment dropped, Space still remembered.
        #expect(loaded.state.entries.isEmpty)
        #expect(loaded.needsRedownload.isEmpty)
        #expect(loaded.state.knownSpaces[5] == Set([9]))
    }

    @Test func skipsMalformedRecordsButLoadsValidOnes() throws {
        let defaults = try temporaryDefaults()
        defer { defaults.cleanup() }

        let goodURL = defaults.directory.appendingPathComponent("good.mp4")
        FileManager.default.createFile(atPath: goodURL.path(percentEncoded: false), contents: Data())
        let store = WallpaperPersistenceStore(userDefaults: defaults.userDefaults)
        defaults.userDefaults.set(
            [
                // Malformed: missing "path" → skipped via `guard ... else { continue }`.
                [
                    "displayID": NSNumber(value: CGDirectDisplayID(1)),
                    "spaceID": NSNumber(value: UInt64(0)),
                ],
                // Valid record loads normally.
                [
                    "displayID": NSNumber(value: CGDirectDisplayID(2)),
                    "spaceID": NSNumber(value: UInt64(0)),
                    "path": goodURL.path(percentEncoded: false),
                ],
            ],
            forKey: "desktopFiles"
        )

        let loaded = store.load()
        #expect(loaded.state.entries == [
            DesktopKey(displayID: 2, spaceID: 0): WallpaperEntry(localURL: goodURL, youtubeOrigin: nil),
        ])
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
