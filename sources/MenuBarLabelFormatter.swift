import Foundation

enum MenuBarLabelFormatter {
    static let maxVisibleCharacters = 30
    private static let ellipsis = "…"

    static func sharedWallpaperTitle(fileName: String) -> String {
        truncateMiddle(fileName, maxLength: maxVisibleCharacters)
    }

    static func desktopWallpaperTitle(index: Int, fileName: String) -> String {
        let prefix = "Desktop \(index): "
        let available = max(8, maxVisibleCharacters - prefix.count)
        return prefix + truncateMiddle(fileName, maxLength: available)
    }

    static func displayHeaderTitle(_ title: String) -> String {
        truncateMiddle(title, maxLength: maxVisibleCharacters)
    }

    static func truncateMiddle(_ value: String, maxLength: Int) -> String {
        guard value.count > maxLength else { return value }
        guard maxLength > ellipsis.count else {
            return String(value.prefix(maxLength))
        }

        let headCount = (maxLength - ellipsis.count) / 2
        let tailCount = maxLength - ellipsis.count - headCount
        return String(value.prefix(headCount)) + ellipsis + String(value.suffix(tailCount))
    }
}
