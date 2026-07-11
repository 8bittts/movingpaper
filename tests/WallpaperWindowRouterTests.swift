import CoreGraphics
import Foundation
import Testing
@testable import MovingPaper

struct WallpaperWindowRouterTests {

    private let a = CGDirectDisplayID(1)
    private let b = CGDirectDisplayID(2)
    private let urlX = URL(filePath: "/tmp/x.mp4")
    private let urlY = URL(filePath: "/tmp/y.mp4")

    @Test func createsControllerForNewlyPlannedDisplay() {
        let actions = WallpaperWindowRouter.reconcileActions(
            connectedDisplayIDs: [a],
            existingURLs: [:],
            plannedURLs: [a: urlX]
        )
        #expect(actions == [.create(a)])
    }

    @Test func repositionsWhenPlannedURLIsUnchanged() {
        // An unchanged URL must NOT recreate the controller (else the video restarts
        // on every space switch).
        let actions = WallpaperWindowRouter.reconcileActions(
            connectedDisplayIDs: [a],
            existingURLs: [a: urlX],
            plannedURLs: [a: urlX]
        )
        #expect(actions == [.reposition(a)])
    }

    @Test func replacesWhenPlannedURLDiffers() {
        let actions = WallpaperWindowRouter.reconcileActions(
            connectedDisplayIDs: [a],
            existingURLs: [a: urlX],
            plannedURLs: [a: urlY]
        )
        #expect(actions == [.replace(a)])
    }

    @Test func removesControllerWhenPlanBecomesNil() {
        let actions = WallpaperWindowRouter.reconcileActions(
            connectedDisplayIDs: [a],
            existingURLs: [a: urlX],
            plannedURLs: [:]
        )
        #expect(actions == [.remove(a)])
    }

    @Test func noActionForConnectedDisplayWithNoPlanAndNoController() {
        let actions = WallpaperWindowRouter.reconcileActions(
            connectedDisplayIDs: [a],
            existingURLs: [:],
            plannedURLs: [:]
        )
        #expect(actions.isEmpty)
    }

    @Test func removesControllerForDisconnectedDisplay() {
        // Display `b` unplugged: its controller must be torn down (window leak otherwise).
        let actions = WallpaperWindowRouter.reconcileActions(
            connectedDisplayIDs: [a],
            existingURLs: [a: urlX, b: urlY],
            plannedURLs: [a: urlX]
        )
        #expect(actions == [.reposition(a), .remove(b)])
    }

    @Test func handlesMixedActionsDeterministically() {
        // a: unchanged → reposition, b: new → create.
        let actions = WallpaperWindowRouter.reconcileActions(
            connectedDisplayIDs: [b, a],
            existingURLs: [a: urlX],
            plannedURLs: [a: urlX, b: urlY]
        )
        #expect(actions == [.reposition(a), .create(b)])
    }
}
