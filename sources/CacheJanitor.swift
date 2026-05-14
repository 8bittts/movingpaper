import Foundation

/// Caps cache directories at a configurable total byte budget. Files are
/// evicted oldest-first by content-modification date. Pure file IO — the
/// caller decides when to run (typically on app launch).
///
/// Photos picker and shuffle caches are intentionally NOT enrolled: their
/// files are unrecoverable once evicted (the original PHAsset reference is
/// not stored), so a stale eviction would orphan a user-visible wallpaper.
/// The YouTube cache is safe to evict — if a wallpaper still references the
/// file, persistence queues a redownload from the saved youtubeOrigin on
/// next launch.
enum CacheJanitor {

    /// 2 GiB. Roughly 4–8 typical 1080p YouTube downloads.
    static let defaultYouTubeBudgetBytes: Int64 = 2 * 1024 * 1024 * 1024

    /// Evict oldest files from `directory` until total bytes ≤ `budgetBytes`.
    /// Returns the number of files deleted (0 if the budget was already met
    /// or the directory does not exist).
    @discardableResult
    static func enforceBudget(
        directory: URL,
        budgetBytes: Int64,
        fileManager: FileManager = .default
    ) -> Int {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return 0
        }

        struct Candidate {
            let url: URL
            let size: Int64
            let modified: Date
        }

        let candidates: [Candidate] = entries.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                  let size = values.fileSize,
                  let modified = values.contentModificationDate
            else { return nil }
            return Candidate(url: url, size: Int64(size), modified: modified)
        }

        let totalSize = candidates.reduce(Int64(0)) { $0 + $1.size }
        guard totalSize > budgetBytes else { return 0 }

        // Oldest first — those are the most likely to be unused.
        let sorted = candidates.sorted { $0.modified < $1.modified }
        var remaining = totalSize
        var deleted = 0

        for candidate in sorted where remaining > budgetBytes {
            do {
                try fileManager.removeItem(at: candidate.url)
                remaining -= candidate.size
                deleted += 1
            } catch {
                // Skip files we can't delete (in-use, perms, etc.).
                continue
            }
        }

        return deleted
    }

    /// Apply the default YouTube cache policy. Safe to call from any actor.
    static func enforceDefaultPolicies() {
        enforceBudget(
            directory: AppPaths.youtubeCache,
            budgetBytes: defaultYouTubeBudgetBytes
        )
    }
}
