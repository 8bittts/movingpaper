import Foundation
import Testing

/// Runs the tracked `.githooks/commit-msg` against sample messages, so the hook
/// that refuses AI attribution cannot rot or lose its executable bit unseen.
@Suite struct CommitMsgHookTests {
    private static let root = URL(filePath: #filePath)
        .deletingLastPathComponent() // tests/
        .deletingLastPathComponent() // repo root
    private static let hook = root.appending(path: ".githooks/commit-msg")
    private static let human = [
        "GIT_AUTHOR_NAME": "Dev", "GIT_AUTHOR_EMAIL": "dev@example.com",
        "GIT_COMMITTER_NAME": "Dev", "GIT_COMMITTER_EMAIL": "dev@example.com",
    ]

    private func run(_ message: String?, identity: [String: String] = human) throws -> (status: Int32, stderr: String) {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "commit-msg-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "COMMIT_EDITMSG")
        if let message { try message.write(to: file, atomically: true, encoding: .utf8) }

        let process = Process()
        process.executableURL = URL(filePath: "/bin/sh")
        process.arguments = [Self.hook.path, file.path]
        process.environment = [
            "PATH": "/usr/bin:/bin", "HOME": directory.path,
            "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null",
        ].merging(identity) { _, new in new }
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = Pipe()
        try process.run()
        let data = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    @Test func hookIsTrackedAndExecutable() throws {
        #expect(FileManager.default.isExecutableFile(atPath: Self.hook.path))
        let setup = try String(contentsOf: Self.root.appending(path: "scripts/setup-hooks.sh"), encoding: .utf8)
        #expect(setup.contains("git config core.hooksPath .githooks"))
    }

    @Test(arguments: [
        "docs: tidy the notes\n",
        "feat: thing\n\nCo-authored-by: Bert Smith <bert@example.com>\n",
        "feat: thing\n\nCo-authored-by: Devin Smith <devin@example.com>\n",
        "docs: forbid AI authors\n\nClaude and Codex trailers are refused.\n",
    ])
    func acceptsHumanCommitsAndHumanCoAuthors(message: String) throws {
        #expect(try run(message).status == 0)
    }

    @Test(arguments: [
        "feat: thing\n\nCo-authored-by: Claude <noreply@anthropic.com>\n",
        "feat: thing\n\nCo-authored-by: Cursor Agent <cursoragent@cursor.com>\n",
        "feat: thing\n\nSigned-off-by: Codex <codex@openai.com>\n",
        "feat: thing\n\nGenerated with Claude Code\n",
        "feat: thing\n\nAI-assisted change\n",
    ])
    func rejectsAgentTrailersAndPhrases(message: String) throws {
        let result = try run(message)
        #expect(result.status == 1)
        #expect(result.stderr.contains("[FAIL] commit-msg"))
    }

    @Test func rejectsAnAgentAuthorOrCommitter() throws {
        var author = Self.human
        author["GIT_AUTHOR_NAME"] = "Cursor Agent"
        author["GIT_AUTHOR_EMAIL"] = "cursoragent@cursor.com"
        #expect(try run("feat: thing\n", identity: author).status == 1)
        var committer = Self.human
        committer["GIT_COMMITTER_EMAIL"] = "noreply@anthropic.com"
        #expect(try run("feat: thing\n", identity: committer).status == 1)
    }

    @Test func failsClosedWithoutAMessageOrAnIdentity() throws {
        #expect(try run(nil).status == 1)
        var nameless = Self.human
        nameless["GIT_AUTHOR_NAME"] = ""
        #expect(try run("feat: thing\n", identity: nameless).status == 1)
    }
}
