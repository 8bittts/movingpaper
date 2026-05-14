import os

/// Category-scoped loggers for MovingPaper. Subsystem is the app's bundle
/// identifier so log entries are filterable via:
///   `log show --predicate 'subsystem == "com.8bittts.movingpaper"'`
///
/// Use sparingly: log meaningful transitions and errors, not routine traffic.
enum Log {
    private static let subsystem = AppIdentity.bundleIdentifier

    static let wallpaper = Logger(subsystem: subsystem, category: "wallpaper")
    static let youtube = Logger(subsystem: subsystem, category: "youtube")
    static let photos = Logger(subsystem: subsystem, category: "photos")
    static let power = Logger(subsystem: subsystem, category: "power")
    static let display = Logger(subsystem: subsystem, category: "display")
    static let updater = Logger(subsystem: subsystem, category: "updater")
}
