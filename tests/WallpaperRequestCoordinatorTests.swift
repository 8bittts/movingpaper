import CoreGraphics
import Foundation
import Testing
@testable import MovingPaper

struct WallpaperRequestCoordinatorTests {

    @Test @MainActor func replacingATargetInvalidatesTheOlderToken() async {
        let coordinator = WallpaperRequestCoordinator()
        var firstContinuation: CheckedContinuation<Void, Never>?
        var secondStarted = false
        var firstStillCurrentAfterReplacement = true

        coordinator.start(for: .allDesktops) { token in
            await withCheckedContinuation { continuation in
                firstContinuation = continuation
            }
            firstStillCurrentAfterReplacement = coordinator.isCurrent(token, for: .allDesktops)
        }

        await Task.yield()

        coordinator.start(for: .allDesktops) { token in
            secondStarted = coordinator.isCurrent(token, for: .allDesktops)
        }

        firstContinuation?.resume()
        await Task.yield()
        await Task.yield()

        #expect(secondStarted)
        #expect(firstStillCurrentAfterReplacement == false)
    }

    @Test @MainActor func cancelAllInvalidatesEveryTrackedTarget() async {
        let coordinator = WallpaperRequestCoordinator()
        var allDesktopsToken: UUID?
        var displayToken: UUID?
        var firstContinuation: CheckedContinuation<Void, Never>?
        var secondContinuation: CheckedContinuation<Void, Never>?

        coordinator.start(for: .allDesktops) { token in
            allDesktopsToken = token
            await withCheckedContinuation { continuation in
                firstContinuation = continuation
            }
        }

        coordinator.start(for: .display(CGDirectDisplayID(42))) { token in
            displayToken = token
            await withCheckedContinuation { continuation in
                secondContinuation = continuation
            }
        }

        await Task.yield()

        if let allDesktopsToken {
            #expect(coordinator.isCurrent(allDesktopsToken, for: .allDesktops))
        } else {
            Issue.record("Missing all-desktops token")
        }

        if let displayToken {
            #expect(coordinator.isCurrent(displayToken, for: .display(CGDirectDisplayID(42))))
        } else {
            Issue.record("Missing display token")
        }

        coordinator.cancelAll()

        if let allDesktopsToken {
            #expect(coordinator.isCurrent(allDesktopsToken, for: .allDesktops) == false)
        }

        if let displayToken {
            #expect(coordinator.isCurrent(displayToken, for: .display(CGDirectDisplayID(42))) == false)
        }

        firstContinuation?.resume()
        secondContinuation?.resume()
        await Task.yield()
    }

    @Test @MainActor func cancelPropagatesCancellationIntoTheRunningTask() async {
        let coordinator = WallpaperRequestCoordinator()
        var started = false
        var sawCancellation = false

        coordinator.start(for: .allDesktops) { _ in
            started = true
            // Suspends until the coordinator cancels the backing Task.
            try? await Task.sleep(for: .seconds(60))
            sawCancellation = Task.isCancelled
        }

        await Task.yield()
        #expect(started)

        coordinator.cancel(.allDesktops)
        // Let the cancelled sleep unwind.
        for _ in 0..<5 { await Task.yield() }

        #expect(sawCancellation)
    }

    @Test @MainActor func normalCompletionClearsTheToken() async {
        let coordinator = WallpaperRequestCoordinator()
        var capturedToken: UUID?

        // Runs to completion immediately; the deferred finish() should clear it.
        coordinator.start(for: .allDesktops) { token in
            capturedToken = token
        }

        for _ in 0..<5 { await Task.yield() }

        if let capturedToken {
            #expect(coordinator.isCurrent(capturedToken, for: .allDesktops) == false)
        } else {
            Issue.record("operation never ran")
        }
    }

    @Test @MainActor func cancelingOneTargetLeavesOtherTargetsCurrent() async {
        let coordinator = WallpaperRequestCoordinator()
        var allDesktopsToken: UUID?
        var displayToken: UUID?
        var firstContinuation: CheckedContinuation<Void, Never>?
        var secondContinuation: CheckedContinuation<Void, Never>?

        coordinator.start(for: .allDesktops) { token in
            allDesktopsToken = token
            await withCheckedContinuation { continuation in
                firstContinuation = continuation
            }
        }

        coordinator.start(for: .display(CGDirectDisplayID(7))) { token in
            displayToken = token
            await withCheckedContinuation { continuation in
                secondContinuation = continuation
            }
        }

        await Task.yield()

        coordinator.cancel(.display(CGDirectDisplayID(7)))

        if let allDesktopsToken {
            #expect(coordinator.isCurrent(allDesktopsToken, for: .allDesktops))
        } else {
            Issue.record("Missing all-desktops token")
        }

        if let displayToken {
            #expect(coordinator.isCurrent(displayToken, for: .display(CGDirectDisplayID(7))) == false)
        } else {
            Issue.record("Missing display token")
        }

        firstContinuation?.resume()
        secondContinuation?.resume()
        await Task.yield()
    }
}
