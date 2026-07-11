import Foundation
import Testing
@testable import MovingPaper

struct CacheJanitorTests {

    @Test func evictsOldestFilesUntilBudgetIsMet() throws {
        let fixture = try CacheFixture()
        defer { fixture.cleanup() }

        try fixture.write(name: "old.mp4", size: 600, modified: -2_000)
        try fixture.write(name: "middle.mp4", size: 500, modified: -1_000)
        try fixture.write(name: "recent.mp4", size: 400, modified: -100)

        let deleted = CacheJanitor.enforceBudget(directory: fixture.directory, budgetBytes: 1_000)

        #expect(deleted == 1)
        #expect(!FileManager.default.fileExists(atPath: fixture.path(for: "old.mp4")))
        #expect(FileManager.default.fileExists(atPath: fixture.path(for: "middle.mp4")))
        #expect(FileManager.default.fileExists(atPath: fixture.path(for: "recent.mp4")))
    }

    @Test func noEvictionWhenBudgetAlreadyMet() throws {
        let fixture = try CacheFixture()
        defer { fixture.cleanup() }

        try fixture.write(name: "a.mp4", size: 100, modified: -100)
        try fixture.write(name: "b.mp4", size: 100, modified: -200)

        let deleted = CacheJanitor.enforceBudget(directory: fixture.directory, budgetBytes: 500)
        #expect(deleted == 0)
        #expect(FileManager.default.fileExists(atPath: fixture.path(for: "a.mp4")))
        #expect(FileManager.default.fileExists(atPath: fixture.path(for: "b.mp4")))
    }

    @Test func noEvictionWhenTotalEqualsBudget() throws {
        let fixture = try CacheFixture()
        defer { fixture.cleanup() }

        try fixture.write(name: "a.mp4", size: 500, modified: -200)
        try fixture.write(name: "b.mp4", size: 500, modified: -100)

        // totalSize == budget → the `totalSize > budgetBytes` guard must not evict.
        let deleted = CacheJanitor.enforceBudget(directory: fixture.directory, budgetBytes: 1_000)
        #expect(deleted == 0)
        #expect(FileManager.default.fileExists(atPath: fixture.path(for: "a.mp4")))
        #expect(FileManager.default.fileExists(atPath: fixture.path(for: "b.mp4")))
    }

    @Test func evictsMultipleFilesUntilUnderBudget() throws {
        let fixture = try CacheFixture()
        defer { fixture.cleanup() }

        try fixture.write(name: "oldest.mp4", size: 400, modified: -3_000)
        try fixture.write(name: "older.mp4", size: 400, modified: -2_000)
        try fixture.write(name: "newest.mp4", size: 400, modified: -1_000)

        // 1200 total, budget 500 → evict the two oldest, leaving 400.
        let deleted = CacheJanitor.enforceBudget(directory: fixture.directory, budgetBytes: 500)
        #expect(deleted == 2)
        #expect(!FileManager.default.fileExists(atPath: fixture.path(for: "oldest.mp4")))
        #expect(!FileManager.default.fileExists(atPath: fixture.path(for: "older.mp4")))
        #expect(FileManager.default.fileExists(atPath: fixture.path(for: "newest.mp4")))
    }

    @Test func neverEvictsProtectedFilesEvenWhenOldestAndOverBudget() throws {
        let fixture = try CacheFixture()
        defer { fixture.cleanup() }

        try fixture.write(name: "in-use.mp4", size: 600, modified: -2_000)   // oldest
        try fixture.write(name: "stale.mp4", size: 600, modified: -100)

        // 1200 total, budget 800. Oldest is in-use → must evict the newer stale file instead.
        let deleted = CacheJanitor.enforceBudget(
            directory: fixture.directory,
            budgetBytes: 800,
            protectedPaths: [fixture.path(for: "in-use.mp4")]
        )

        #expect(deleted == 1)
        #expect(FileManager.default.fileExists(atPath: fixture.path(for: "in-use.mp4")))
        #expect(!FileManager.default.fileExists(atPath: fixture.path(for: "stale.mp4")))
    }

    @Test func pruneUnreferencedRemovesOnlyOrphanedFiles() throws {
        let fixture = try CacheFixture()
        defer { fixture.cleanup() }

        try fixture.write(name: "in-use.mp4", size: 10, modified: -100)
        try fixture.write(name: "orphan-a.mp4", size: 10, modified: -100)
        try fixture.write(name: "orphan-b.mp4", size: 10, modified: -100)

        let deleted = CacheJanitor.pruneUnreferenced(
            directory: fixture.directory,
            referencedPaths: [fixture.path(for: "in-use.mp4")]
        )

        #expect(deleted == 2)
        #expect(FileManager.default.fileExists(atPath: fixture.path(for: "in-use.mp4")))
        #expect(!FileManager.default.fileExists(atPath: fixture.path(for: "orphan-a.mp4")))
        #expect(!FileManager.default.fileExists(atPath: fixture.path(for: "orphan-b.mp4")))
    }

    @Test func missingDirectoryIsHandledGracefully() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MovingPaperTests-missing-\(UUID().uuidString)", isDirectory: true)
        #expect(CacheJanitor.enforceBudget(directory: url, budgetBytes: 1) == 0)
    }
}

private struct CacheFixture {
    let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MovingPaperJanitorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func write(name: String, size: Int, modified secondsAgo: TimeInterval) throws {
        let url = directory.appendingPathComponent(name)
        try Data(count: size).write(to: url)
        let date = Date().addingTimeInterval(secondsAgo)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path(percentEncoded: false))
    }

    func path(for name: String) -> String {
        directory.appendingPathComponent(name).path(percentEncoded: false)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: directory)
    }
}
