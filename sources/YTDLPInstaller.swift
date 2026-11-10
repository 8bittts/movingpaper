import CryptoKit
import Foundation

/// Pins, verifies, and installs the yt-dlp binary used by `YouTubeDownloader`.
enum YTDLPInstaller {
    /// Pinned yt-dlp release. Bump both fields together — the SHA-256 is checked
    /// against the downloaded binary before it's installed and made executable.
    /// Refresh via `curl -fsSL https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest`
    /// when YouTube site changes break the current pinned version.
    static let pinnedVersion = "2026.03.17"
    static let pinnedSHA256 = "e80c47b3ce712acee51d5e3d4eace2d181b44d38f1942c3a32e3c7ff53cd9ed5"

    static func sha256Hex(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    #if DEBUG
    /// A dev-tree yt-dlp binary, relative to the working directory. Any version,
    /// trusted as-is, so only debug builds look for it: a release build must not
    /// run whatever sits at a path the launching directory controls.
    private static var developerBinaryPath: String? {
        let devPath = "tools/yt-dlp/yt-dlp"
        return FileManager.default.fileExists(atPath: devPath) ? devPath : nil
    }
    #endif

    /// Resolve a trusted yt-dlp binary path: an installed copy **re-verified
    /// against the pinned SHA-256** (so a corrupt or pin-stale binary is never
    /// executed and is re-downloaded), else a fresh download+verify+install.
    /// Debug builds prefer a dev-tree binary. Runs off the main actor, so the
    /// 40 MB hash + write never block it; only reached on a cache miss, so
    /// cached videos never pay it.
    static func ensureYTDLP() async -> String? {
        #if DEBUG
        if let devPath = developerBinaryPath { return devPath }
        #endif

        let installURL = AppPaths.ytdlpBinary
        let installedPath = installURL.path(percentEncoded: false)

        if FileManager.default.fileExists(atPath: installedPath) {
            if let data = try? Data(contentsOf: installURL), sha256Hex(of: data) == pinnedSHA256 {
                return installedPath
            }
            // Corrupt, tampered, or stale after a pin bump — discard and re-fetch.
            Log.youtube.error("Installed yt-dlp failed SHA-256 verification; re-downloading")
            try? FileManager.default.removeItem(at: installURL)
        }

        return await downloadAndInstallYTDLP()
    }

    private static func downloadAndInstallYTDLP() async -> String? {
        let installURL = AppPaths.ytdlpBinary
        let dir = installURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let downloadURL = URL(string:
            "https://github.com/yt-dlp/yt-dlp/releases/download/\(pinnedVersion)/yt-dlp_macos"
        )!
        do {
            let (data, response) = try await URLSession.shared.data(from: downloadURL)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return nil
            }
            guard sha256Hex(of: data) == pinnedSHA256 else {
                Log.youtube.error("yt-dlp SHA-256 mismatch for pinned version \(pinnedVersion, privacy: .public); refusing to install")
                return nil
            }
            // Atomic write: a crash/disk-full mid-write can't leave a truncated,
            // permanently-poisoned binary that the existence-only path check trusts.
            try data.write(to: installURL, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: installURL.path(percentEncoded: false)
            )
            return installURL.path(percentEncoded: false)
        } catch {
            return nil
        }
    }
}
