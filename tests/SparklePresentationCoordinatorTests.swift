import AppKit
import Testing
@testable import MovingPaper

@MainActor
private final class MockAppActivationController: AppActivationControlling {
    var activationPolicy: NSApplication.ActivationPolicy
    var activationCalls: [Bool] = []
    var policyChanges: [NSApplication.ActivationPolicy] = []

    init(activationPolicy: NSApplication.ActivationPolicy) {
        self.activationPolicy = activationPolicy
    }

    func setActivationPolicy(_ policy: NSApplication.ActivationPolicy) {
        activationPolicy = policy
        policyChanges.append(policy)
    }

    func activate(ignoringOtherApps: Bool) {
        activationCalls.append(ignoringOtherApps)
    }
}

struct SparklePresentationCoordinatorTests {

    @Test @MainActor func manualChecksStayDockless() {
        let app = MockAppActivationController(activationPolicy: .accessory)
        let coordinator = SparklePresentationCoordinator(app: app)

        coordinator.beginUserInitiatedCheck()
        coordinator.willShowModalAlert()

        #expect(app.policyChanges.isEmpty)
        #expect(app.activationCalls == [true, true])
        #expect(app.activationPolicy == .accessory)
    }

    @Test @MainActor func updatePresentationPromotesAccessoryAppsUntilSessionFinishes() {
        let app = MockAppActivationController(activationPolicy: .accessory)
        let coordinator = SparklePresentationCoordinator(app: app)

        coordinator.willShowUpdate()
        #expect(app.policyChanges == [.regular])
        #expect(app.activationCalls == [true])
        #expect(app.activationPolicy == .regular)

        coordinator.finishUpdateSession()
        #expect(app.policyChanges == [.regular, .accessory])
        #expect(app.activationPolicy == .accessory)
    }

    @Test @MainActor func updatePresentationDoesNotDemoteRegularApps() {
        let app = MockAppActivationController(activationPolicy: .regular)
        let coordinator = SparklePresentationCoordinator(app: app)

        coordinator.willShowUpdate()
        coordinator.finishUpdateSession()

        #expect(app.policyChanges.isEmpty)
        #expect(app.activationCalls == [true])
        #expect(app.activationPolicy == .regular)
    }
}
