import Foundation
import Testing

/// Runs `bump_cask` from `scripts/lib/cask.sh` on a copy of the real Cask, so a
/// release cannot pin the Cask to the wrong build or skip the pin unseen.
@Suite struct CaskBumpTests {
    private static let root = URL(filePath: #filePath)
        .deletingLastPathComponent() // tests/
        .deletingLastPathComponent() // repo root
    private static let library = root.appending(path: "scripts/lib/cask.sh")
    private static let cask = root.appending(path: "Casks/movingpaper.rb")
    private static let checksum = String(repeating: "ab", count: 32)

    private func bump(cask: String?, version: String, checksumLine: String?) throws -> (status: Int32, cask: String) {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "cask-bump-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let caskFile = directory.appending(path: "cask.rb")
        let checksumFile = directory.appending(path: "build.sha256")
        if let cask { try cask.write(to: caskFile, atomically: true, encoding: .utf8) }
        if let checksumLine { try checksumLine.write(to: checksumFile, atomically: true, encoding: .utf8) }

        let process = Process()
        process.executableURL = URL(filePath: "/bin/bash")
        process.arguments = [
            "-c",
            "fail() { echo \"$1\" >&2; exit 1; }; step() { :; }; source \"$0\"; bump_cask \"$1\" \"$2\" \"$3\"",
            Self.library.path, caskFile.path, version, checksumFile.path,
        ]
        process.standardError = Pipe()
        process.standardOutput = Pipe()
        try process.run()
        process.waitUntilExit()
        let result = (try? String(contentsOf: caskFile, encoding: .utf8)) ?? ""
        return (process.terminationStatus, result)
    }

    @Test func pinsTheVersionAndChecksumAndNothingElse() throws {
        let original = try String(contentsOf: Self.cask, encoding: .utf8)
        let result = try bump(cask: original, version: "9.999", checksumLine: "\(Self.checksum)  App-9.999.dmg\n")
        #expect(result.status == 0)
        #expect(result.cask.contains("  version \"9.999\"\n"))
        #expect(result.cask.contains("  sha256 \"\(Self.checksum)\"\n"))
        let before = original.split(separator: "\n")
        let after = result.cask.split(separator: "\n")
        #expect(before.count == after.count)
        #expect(zip(before, after).filter { $0 != $1 }.count == 2)
    }

    @Test func failsClosedOnBadInput() throws {
        let original = try String(contentsOf: Self.cask, encoding: .utf8)
        let good = "\(Self.checksum)  App.dmg\n"
        #expect(try bump(cask: original, version: "9.999", checksumLine: "not-a-checksum  App.dmg\n").status == 1)
        #expect(try bump(cask: original, version: "9.999", checksumLine: nil).status == 1)
        #expect(try bump(cask: nil, version: "9.999", checksumLine: good).status == 1)
        #expect(try bump(cask: original, version: "v9.999", checksumLine: good).status == 1)
        #expect(try bump(cask: "cask \"x\" do\nend\n", version: "9.999", checksumLine: good).status == 1)
    }

    @Test func theReleaseScriptPinsTheCaskBeforeItCommits() throws {
        let release = try String(contentsOf: Self.root.appending(path: "scripts/release-movingpaper.sh"), encoding: .utf8)
        let bump = try #require(release.range(of: "bump_cask \"$CASK_FILE\""))
        let commit = try #require(release.range(of: "git commit -m \"release:"))
        #expect(bump.lowerBound < commit.lowerBound)
        #expect(release.contains("source \"${REPO_ROOT}/scripts/lib/cask.sh\""))
        #expect(release[bump.upperBound..<commit.lowerBound].contains("\"$CASK_FILE\""))
    }
}
