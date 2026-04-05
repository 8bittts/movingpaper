import Foundation

/// Extracts video IDs from YouTube URL strings.
enum YouTubeURLParser {

    /// Supported YouTube URL patterns:
    ///   youtube.com/watch?v=ID
    ///   youtu.be/ID
    ///   youtube.com/shorts/ID
    ///   youtube.com/embed/ID
    ///   youtube.com/v/ID
    ///   m.youtube.com/watch?v=ID
    private static let patterns: [(regex: NSRegularExpression, group: Int)] = {
        let defs: [(String, Int)] = [
            (#"(?:youtube\.com|m\.youtube\.com)/watch\?.*v=([A-Za-z0-9_-]{11})"#, 1),
            (#"youtu\.be/([A-Za-z0-9_-]{11})"#, 1),
            (#"(?:youtube\.com|m\.youtube\.com)/shorts/([A-Za-z0-9_-]{11})"#, 1),
            (#"(?:youtube\.com|m\.youtube\.com)/embed/([A-Za-z0-9_-]{11})"#, 1),
            (#"(?:youtube\.com|m\.youtube\.com)/v/([A-Za-z0-9_-]{11})"#, 1),
        ]
        return defs.compactMap { pattern, group in
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
            return (regex, group)
        }
    }()

    /// Extract the 11-character video ID from a YouTube URL string.
    static func videoID(from string: String) -> String? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        let range = NSRange(trimmed.startIndex..., in: trimmed)

        for (regex, group) in patterns {
            if let match = regex.firstMatch(in: trimmed, range: range),
               let idRange = Range(match.range(at: group), in: trimmed) {
                return String(trimmed[idRange])
            }
        }
        return nil
    }

    /// Whether the string looks like a YouTube URL.
    static func isYouTubeURL(_ string: String) -> Bool {
        videoID(from: string) != nil
    }
}
