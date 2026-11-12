import AppKit
import Testing
@testable import MovingPaper

struct AppPresentationTests {

    @Test func noHoldsMeansAccessory() {
        #expect(AppPresentation.Holds().activationPolicy == .accessory)
    }

    @Test func closingOneSurfaceKeepsTheAppRegularWhileAnotherIsUp() {
        var holds = AppPresentation.Holds()
        holds.begin(.updater)
        holds.begin(.modal)
        holds.end(.modal)
        #expect(holds.activationPolicy == .regular)
        holds.end(.updater)
        #expect(holds.activationPolicy == .accessory)
    }

    @Test func holdsOfOneReasonAreCounted() {
        var holds = AppPresentation.Holds()
        holds.begin(.modal)
        holds.begin(.modal)
        holds.end(.modal)
        #expect(holds.contains(.modal))
        holds.end(.modal)
        #expect(!holds.contains(.modal))
    }

    @Test func anExtraEndIsIgnored() {
        var holds = AppPresentation.Holds()
        holds.end(.dockSession)
        holds.begin(.photosPicker)
        holds.end(.dockSession)
        #expect(holds.contains(.photosPicker))
        #expect(!holds.contains(.dockSession))
    }
}
