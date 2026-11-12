import AppKit
import CoreGraphics

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}

/// Display identity that survives a restart. Apple: a `CGDirectDisplayID`
/// "typically remains constant until the machine is restarted", so saved
/// assignments carry the display's UUID and are mapped back to the current ID.
struct DisplayIdentity: Sendable {
    var uuid: @Sendable (CGDirectDisplayID) -> String?
    var connectedDisplayID: @Sendable (_ uuid: String) -> CGDirectDisplayID?

    static let system = DisplayIdentity(
        uuid: { systemUUID(for: $0) },
        connectedDisplayID: { uuid in onlineDisplayIDs().first { systemUUID(for: $0) == uuid } }
    )

    static func systemUUID(for displayID: CGDirectDisplayID) -> String? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }

    private static func onlineDisplayIDs() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(count)))
    }
}
