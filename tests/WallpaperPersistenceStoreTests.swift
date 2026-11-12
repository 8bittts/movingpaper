import CoreGraphics
import Foundation
import Testing
@testable import MovingPaper

extension DisplayIdentity {
    /// No display has a UUID, so records keep their saved display IDs.
    static let none = DisplayIdentity(uuid: { _ in nil }, connectedDisplayID: { _ in nil })
}

struct WallpaperPersistenceStoreTests {

    @Test func savesAndLoadsExistingAssignments() throws {
        let defaults = try temporaryDefaults()
        defer { defaults.cleanup() }

        let wallpaperURL = defaults.directory.appendingPathComponent("wallpaper.mp4")
        FileManager.default.createFile(atPath: wallpaperURL.path(percentEncoded: false), contents: Data())

        let key = DesktopKey(displayID: 99, spaceID: 42)
        let store = WallpaperPersistenceStore(userDefaults: defaults.userDefaults, displayIdentity: .none)

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
        let store = WallpaperPersistenceStore(userDefaults: defaults.userDefaults, displayIdentity: .none)
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
            WallpaperRedownloadRequest(
                key: key,
                youtubeURL: "https://youtu.be/dQw4w9WgXcQ",
                localURL: URL(filePath: missingPath)
            ),
        ])
    }

    @Test func saveRePersistsPendingRedownloadsSoTheySurviveUnrelatedSaves() throws {
        let defaults = try temporaryDefaults()
        defer { defaults.cleanup() }

        let missingPath = defaults.directory.appendingPathComponent("gone.mp4").path(percentEncoded: false)
        let store = WallpaperPersistenceStore(userDefaults: defaults.userDefaults, displayIdentity: .none)
        defaults.userDefaults.set(
            [[
                "displayID": NSNumber(value: CGDirectDisplayID(7)),
                "spaceID": NSNumber(value: UInt64(3)),
                "path": missingPath,
                "youtubeURL": "https://youtu.be/dQw4w9WgXcQ",
            ]],
            forKey: "desktopFiles"
        )

        // Launch: the missing YouTube-backed file is queued for redownload.
        let loaded = store.load()
        #expect(loaded.needsRedownload.count == 1)

        // An unrelated save (e.g. toggling mute) happens before the redownload
        // finishes. The pending record must survive, not be erased.
        store.save(
            mode: loaded.mode,
            isMuted: false,
            state: loaded.state,
            pendingRedownloads: loaded.needsRedownload
        )

        let reloaded = store.load()
        #expect(reloaded.needsRedownload == loaded.needsRedownload)
    }

    @Test func saveDoesNotReemitPendingForKeysNowAssigned() throws {
        let defaults = try temporaryDefaults()
        defer { defaults.cleanup() }

        let realURL = defaults.directory.appendingPathComponent("resolved.mp4")
        FileManager.default.createFile(atPath: realURL.path(percentEncoded: false), contents: Data())
        let key = DesktopKey(displayID: 7, spaceID: 3)
        let store = WallpaperPersistenceStore(userDefaults: defaults.userDefaults, displayIdentity: .none)

        // The redownload has resolved: the key now has a real entry.
        var state = WallpaperState()
        state.setEntry(WallpaperEntry(localURL: realURL, youtubeOrigin: "https://youtu.be/x"), for: key)
        let stalePending = WallpaperRedownloadRequest(
            key: key,
            youtubeURL: "https://youtu.be/x",
            localURL: URL(filePath: "/missing.mp4")
        )

        store.save(mode: .perDesktop, isMuted: true, state: state, pendingRedownloads: [stalePending])

        let reloaded = store.load()
        // The resolved entry loads; the stale pending record for the same key is dropped.
        #expect(reloaded.state.entries == [key: WallpaperEntry(localURL: realURL, youtubeOrigin: "https://youtu.be/x")])
        #expect(reloaded.needsRedownload.isEmpty)
    }

    @Test func defaultsMissingModeAndMuteToCurrentBehavior() throws {
        let defaults = try temporaryDefaults()
        defer { defaults.cleanup() }

        let loaded = WallpaperPersistenceStore(userDefaults: defaults.userDefaults, displayIdentity: .none).load()
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
        _ = WallpaperPersistenceStore(userDefaults: defaults.userDefaults, displayIdentity: .none).load()
        #expect(
            defaults.userDefaults.integer(forKey: "persistenceSchemaVersion")
                == WallpaperPersistenceStore.currentSchemaVersion
        )
    }

    @Test func dropsMissingLocalFileWithNoYouTubeOrigin() throws {
        let defaults = try temporaryDefaults()
        defer { defaults.cleanup() }

        let missingPath = defaults.directory.appendingPathComponent("gone.mp4").path(percentEncoded: false)
        let store = WallpaperPersistenceStore(userDefaults: defaults.userDefaults, displayIdentity: .none)
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

    @Test func persistedRecordRoundTripsSchemaV1Keys() {
        let key = DesktopKey(displayID: 9, spaceID: 4)
        let record = WallpaperPersistedRecord(
            key: key,
            path: "/tmp/loop.mp4",
            youtubeURL: "https://youtu.be/x"
        )
        let object = record.plistObject()
        #expect(object["displayID"] as? NSNumber == NSNumber(value: CGDirectDisplayID(9)))
        #expect(object["spaceID"] as? NSNumber == NSNumber(value: UInt64(4)))
        #expect(object["path"] as? String == "/tmp/loop.mp4")
        #expect(object["youtubeURL"] as? String == "https://youtu.be/x")
        #expect(Set(object.keys) == ["displayID", "spaceID", "path", "youtubeURL"])

        let parsed = WallpaperPersistedRecord(plistObject: object)
        #expect(parsed == record)
        #expect(parsed?.key == key)

        let localOnly = WallpaperPersistedRecord(key: key, path: "/tmp/loop.mp4", youtubeURL: nil)
        #expect(Set(localOnly.plistObject().keys) == ["displayID", "spaceID", "path"])
        #expect(WallpaperPersistedRecord(plistObject: ["displayID": NSNumber(value: 1)]) == nil)
    }

    @Test func skipsMalformedRecordsButLoadsValidOnes() throws {
        let defaults = try temporaryDefaults()
        defer { defaults.cleanup() }

        let goodURL = defaults.directory.appendingPathComponent("good.mp4")
        FileManager.default.createFile(atPath: goodURL.path(percentEncoded: false), contents: Data())
        let store = WallpaperPersistenceStore(userDefaults: defaults.userDefaults, displayIdentity: .none)
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

    /// One display whose ID changed across a restart: saved as 5, now 7.
    private static let restartedDisplay = DisplayIdentity(
        uuid: { $0 == 5 || $0 == 7 ? "UUID-A" : nil },
        connectedDisplayID: { $0 == "UUID-A" ? 7 : nil }
    )

    @Test func v1RecordsLoadByDisplayIDAndGainADisplayUUIDOnTheNextSave() throws {
        let defaults = try temporaryDefaults()
        defer { defaults.cleanup() }

        let wallpaperURL = defaults.directory.appendingPathComponent("v1.mp4")
        FileManager.default.createFile(atPath: wallpaperURL.path(percentEncoded: false), contents: Data())
        defaults.userDefaults.set(1, forKey: "persistenceSchemaVersion")
        defaults.userDefaults.set(
            [[
                "displayID": NSNumber(value: CGDirectDisplayID(5)),
                "spaceID": NSNumber(value: UInt64(3)),
                "path": wallpaperURL.path(percentEncoded: false),
            ]],
            forKey: "desktopFiles"
        )
        let store = WallpaperPersistenceStore(userDefaults: defaults.userDefaults, displayIdentity: Self.restartedDisplay)

        let loaded = store.load()
        let key = DesktopKey(displayID: 5, spaceID: 3)
        #expect(loaded.state.entries[key]?.localURL == wallpaperURL)
        #expect(defaults.userDefaults.integer(forKey: "persistenceSchemaVersion") == 2)

        store.save(mode: loaded.mode, isMuted: loaded.isMuted, state: loaded.state)
        let saved = defaults.userDefaults.array(forKey: "desktopFiles") as? [[String: Any]]
        #expect(saved?.first?["displayUUID"] as? String == "UUID-A")
        #expect(saved?.first?["displayID"] as? NSNumber == NSNumber(value: CGDirectDisplayID(5)))
    }

    @Test func aDisplayWhoseIDChangedAfterARestartKeepsItsWallpaper() throws {
        let defaults = try temporaryDefaults()
        defer { defaults.cleanup() }

        let wallpaperURL = defaults.directory.appendingPathComponent("v2.mp4")
        FileManager.default.createFile(atPath: wallpaperURL.path(percentEncoded: false), contents: Data())
        defaults.userDefaults.set(2, forKey: "persistenceSchemaVersion")
        defaults.userDefaults.set(
            [[
                "displayID": NSNumber(value: CGDirectDisplayID(5)),
                "spaceID": NSNumber(value: UInt64(3)),
                "path": wallpaperURL.path(percentEncoded: false),
                "displayUUID": "UUID-A",
            ]],
            forKey: "desktopFiles"
        )

        let loaded = WallpaperPersistenceStore(
            userDefaults: defaults.userDefaults,
            displayIdentity: Self.restartedDisplay
        ).load()

        #expect(loaded.state.entries.keys.map { $0 } == [DesktopKey(displayID: 7, spaceID: 3)])
        #expect(loaded.state.knownSpaces[7] == Set([3]))
        #expect(loaded.state.knownSpaces[5] == nil)
    }

    @Test func aMovedUserFileIsFoundThroughItsBookmark() throws {
        let defaults = try temporaryDefaults()
        defer { defaults.cleanup() }

        let original = defaults.directory.appendingPathComponent("before.mp4")
        let moved = defaults.directory.appendingPathComponent("after.mp4")
        FileManager.default.createFile(atPath: original.path(percentEncoded: false), contents: Data([1]))
        let store = WallpaperPersistenceStore(userDefaults: defaults.userDefaults, displayIdentity: .none)
        let key = DesktopKey(displayID: 4)
        var state = WallpaperState()
        state.setEntry(WallpaperEntry(localURL: original, youtubeOrigin: nil), for: key)
        store.save(mode: .allDesktops, isMuted: true, state: state)

        try FileManager.default.moveItem(at: original, to: moved)
        let loaded = store.load()

        #expect(loaded.state.entries[key]?.localURL.resolvingSymlinksInPath() == moved.resolvingSymlinksInPath())
    }

    @Test func youTubeRecordsCarryNoBookmark() throws {
        let defaults = try temporaryDefaults()
        defer { defaults.cleanup() }

        let file = defaults.directory.appendingPathComponent("yt.mp4")
        FileManager.default.createFile(atPath: file.path(percentEncoded: false), contents: Data([1]))
        var state = WallpaperState()
        state.setEntry(WallpaperEntry(localURL: file, youtubeOrigin: "https://youtu.be/x"), for: DesktopKey(displayID: 4))
        WallpaperPersistenceStore(userDefaults: defaults.userDefaults, displayIdentity: .none)
            .save(mode: .allDesktops, isMuted: true, state: state)

        let saved = defaults.userDefaults.array(forKey: "desktopFiles") as? [[String: Any]]
        #expect(saved?.first?["bookmark"] == nil)
    }

    @Test func aDisconnectedDisplayKeepsItsSavedID() throws {
        let defaults = try temporaryDefaults()
        defer { defaults.cleanup() }

        let wallpaperURL = defaults.directory.appendingPathComponent("away.mp4")
        FileManager.default.createFile(atPath: wallpaperURL.path(percentEncoded: false), contents: Data())
        defaults.userDefaults.set(
            [[
                "displayID": NSNumber(value: CGDirectDisplayID(9)),
                "spaceID": NSNumber(value: UInt64(0)),
                "path": wallpaperURL.path(percentEncoded: false),
                "displayUUID": "UUID-UNPLUGGED",
            ]],
            forKey: "desktopFiles"
        )

        let loaded = WallpaperPersistenceStore(
            userDefaults: defaults.userDefaults,
            displayIdentity: Self.restartedDisplay
        ).load()

        #expect(loaded.state.entries[DesktopKey(displayID: 9)]?.localURL == wallpaperURL)
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
