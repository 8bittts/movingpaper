import Foundation

/// Extracts video IDs from YouTube URL strings.
enum YouTubeURLParser {

    private static let allowedHosts = Set(["youtube.com", "www.youtube.com", "m.youtube.com"])
    private static let allowedSchemes = Set(["http", "https"])
    private static let shortHost = "youtu.be"
    /// Path prefixes that carry the video ID as the next component.
    private static let idRoutes = Set(["shorts", "embed", "v"])
    private static let allowedIDCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")

    /// Extract the 11-character video ID from a YouTube URL string.
    static func videoID(from string: String) -> String? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = normalizedURLCandidate(from: trimmed)

        guard let components = URLComponents(string: candidate),
              let scheme = components.scheme?.lowercased(),
              allowedSchemes.contains(scheme),
              let host = components.host?.lowercased() else {
            return nil
        }

        let pathParts = components.path.split(separator: "/").map(String.init)

        if host == shortHost {
            return validVideoID(from: pathParts.first)
        }

        guard allowedHosts.contains(host) else { return nil }

        if components.path == "/watch" {
            return components.queryItems?
                .first { $0.name == "v" }
                .flatMap { validVideoID(from: $0.value) }
        }
        guard let route = pathParts.first, idRoutes.contains(route) else { return nil }
        return validVideoID(from: pathParts.dropFirst().first)
    }

    private static func normalizedURLCandidate(from string: String) -> String {
        guard !string.isEmpty else { return string }
        if string.contains("://") { return string }
        return "https://\(string)"
    }

    private static func validVideoID(from value: String?) -> String? {
        guard let value, value.count == 11 else {
            return nil
        }
        guard value.unicodeScalars.allSatisfy({ allowedIDCharacters.contains($0) }) else {
            return nil
        }
        return value
    }

    /// Whether the string looks like a YouTube URL.
    static func isYouTubeURL(_ string: String) -> Bool {
        videoID(from: string) != nil
    }
}
