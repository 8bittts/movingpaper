import AppKit
import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation

/// Reconciles per-display `WallpaperWindowController` instances against a plan.
/// Knows nothing about modes, Spaces, or persistence — the caller hands in a
/// plan keyed by `CGDirectDisplayID` and reads back current playback positions
/// keyed the same way, then translates to its own state keys.
@MainActor
final class WallpaperWindowRouter {

    struct Plan: Equatable {
        let url: URL
        let type: WallpaperFileType
        let resumeTime: CMTime?
    }

    private var controllers: [CGDirectDisplayID: WallpaperWindowController] = [:]
    private(set) var isMuted: Bool = true

    init(isMuted: Bool = true) {
        self.isMuted = isMuted
    }

    /// Bring every connected screen in sync with its plan, creating/replacing
    /// controllers where the URL differs and tearing down ones whose screens
    /// are gone or whose plan is nil.
    func reconcile(screens: [NSScreen], plan: (CGDirectDisplayID) -> Plan?) {
        var seen = Set<CGDirectDisplayID>()

        for screen in screens {
            guard let displayID = screen.displayID else { continue }
            seen.insert(displayID)

            guard let plan = plan(displayID) else {
                if let controller = controllers.removeValue(forKey: displayID) {
                    controller.close()
                }
                continue
            }

            if let existing = controllers[displayID] {
                if existing.currentURL == plan.url {
                    existing.reposition(to: screen)
                    continue
                }
                existing.close()
            }

            controllers[displayID] = makeController(screen: screen, plan: plan)
        }

        for displayID in controllers.keys where !seen.contains(displayID) {
            controllers.removeValue(forKey: displayID)?.close()
        }
    }

    func setMuted(_ muted: Bool) {
        isMuted = muted
        for controller in controllers.values {
            controller.player?.isMuted = muted
        }
    }

    /// Read each live video's current playback time. Caller stores them keyed
    /// by `DesktopKey` according to its mode/space awareness.
    func currentPlaybackTimes() -> [CGDirectDisplayID: CMTime] {
        var times: [CGDirectDisplayID: CMTime] = [:]
        for (displayID, controller) in controllers {
            guard controller.currentURL != nil else { continue }
            if let time = controller.player?.currentTime(), time.isValid, time.seconds > 0 {
                times[displayID] = time
            }
        }
        return times
    }

    /// Close every controller and clear the routing table.
    func closeAll() {
        for controller in controllers.values {
            controller.close()
        }
        controllers.removeAll()
    }

    /// Remove a single display's controller without disturbing the others.
    /// Used when the caller wants to clear one slot (e.g. per-desktop "Remove").
    func closeController(for displayID: CGDirectDisplayID) {
        controllers.removeValue(forKey: displayID)?.close()
    }

    private func makeController(screen: NSScreen, plan: Plan) -> WallpaperWindowController {
        let controller = WallpaperWindowController(screen: screen)
        switch plan.type {
        case .video:
            let view = VideoWallpaperView(
                url: plan.url,
                isMuted: isMuted,
                resumeTime: plan.resumeTime
            )
            controller.show(content: view, url: plan.url)
            // VideoPlayerNSView owns playback resume internally; we only need the
            // player reference for mute toggle and position save at teardown.
            DispatchQueue.main.async { [weak controller] in
                guard let controller,
                      let videoView = Self.findVideoView(in: controller.panel.contentView)
                else { return }
                controller.player = videoView.player
            }
        case .gif:
            controller.show(content: GIFWallpaperView(url: plan.url), url: plan.url)
        }
        return controller
    }

    private static func findVideoView(in view: NSView?) -> VideoPlayerNSView? {
        guard let view else { return nil }
        if let v = view as? VideoPlayerNSView { return v }
        for sub in view.subviews {
            if let found = findVideoView(in: sub) { return found }
        }
        return nil
    }
}
