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

    /// One reconciliation outcome for a single display. Kept separate from the
    /// AppKit effects so the branch matrix is unit-testable.
    enum ReconcileAction: Equatable {
        case create(CGDirectDisplayID)
        case reposition(CGDirectDisplayID)
        case replace(CGDirectDisplayID)
        case remove(CGDirectDisplayID)
    }

    /// Pure decision: given the connected displays, the URL each existing
    /// controller is showing, and the planned URL per display, decide what to do.
    /// Deterministic order (connected sorted, then disconnected removals sorted).
    nonisolated static func reconcileActions(
        connectedDisplayIDs: [CGDirectDisplayID],
        existingURLs: [CGDirectDisplayID: URL],
        plannedURLs: [CGDirectDisplayID: URL]
    ) -> [ReconcileAction] {
        var actions: [ReconcileAction] = []

        for id in connectedDisplayIDs.sorted() {
            if let planned = plannedURLs[id] {
                if let existing = existingURLs[id] {
                    actions.append(existing == planned ? .reposition(id) : .replace(id))
                } else {
                    actions.append(.create(id))
                }
            } else if existingURLs[id] != nil {
                actions.append(.remove(id))
            }
        }

        let connected = Set(connectedDisplayIDs)
        for id in existingURLs.keys.sorted() where !connected.contains(id) {
            actions.append(.remove(id))
        }

        return actions
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
        let screensByID = Dictionary(
            uniqueKeysWithValues: screens.compactMap { screen in
                screen.displayID.map { ($0, screen) }
            }
        )
        let plansByID = screensByID.keys.reduce(into: [CGDirectDisplayID: Plan]()) { acc, id in
            if let plan = plan(id) { acc[id] = plan }
        }
        let existingURLs = controllers.compactMapValues { $0.currentURL }

        let actions = Self.reconcileActions(
            connectedDisplayIDs: Array(screensByID.keys),
            existingURLs: existingURLs,
            plannedURLs: plansByID.mapValues { $0.url }
        )

        for action in actions {
            switch action {
            case .remove(let id):
                controllers.removeValue(forKey: id)?.close()
            case .reposition(let id):
                if let screen = screensByID[id] {
                    controllers[id]?.reposition(to: screen)
                }
            case .create(let id):
                if let screen = screensByID[id], let plan = plansByID[id] {
                    controllers[id] = makeController(screen: screen, plan: plan)
                }
            case .replace(let id):
                controllers[id]?.close()
                if let screen = screensByID[id], let plan = plansByID[id] {
                    controllers[id] = makeController(screen: screen, plan: plan)
                }
            }
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
            let videoView = VideoPlayerNSView()
            videoView.loadVideo(url: plan.url, resumeTime: plan.resumeTime)
            videoView.setMuted(isMuted)
            controller.show(videoView, url: plan.url)
            controller.player = videoView.player
        case .gif:
            let gifView = GIFAnimationNSView()
            gifView.loadGIF(url: plan.url)
            controller.show(gifView, url: plan.url)
        }
        return controller
    }
}
