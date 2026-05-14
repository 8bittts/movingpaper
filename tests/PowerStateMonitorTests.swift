import Foundation
import Testing
@testable import MovingPaper

struct PowerStateMonitorTests {

    /// `shouldPause` is the pure decision function the monitor uses; it captures
    /// the policy we ship without depending on a live notification center.
    @Test func nominalAndFairThermalStatesDoNotPause() {
        #expect(PowerStateMonitor.shouldPause(processInfo: FakeProcessInfo(low: false, thermal: .nominal)) == false)
        #expect(PowerStateMonitor.shouldPause(processInfo: FakeProcessInfo(low: false, thermal: .fair)) == false)
    }

    @Test func seriousAndCriticalThermalStatesPause() {
        #expect(PowerStateMonitor.shouldPause(processInfo: FakeProcessInfo(low: false, thermal: .serious)) == true)
        #expect(PowerStateMonitor.shouldPause(processInfo: FakeProcessInfo(low: false, thermal: .critical)) == true)
    }

    @Test func lowPowerModePausesRegardlessOfThermalState() {
        #expect(PowerStateMonitor.shouldPause(processInfo: FakeProcessInfo(low: true, thermal: .nominal)) == true)
        #expect(PowerStateMonitor.shouldPause(processInfo: FakeProcessInfo(low: true, thermal: .critical)) == true)
    }

    @Test @MainActor func startEmitsInitialVerdictSynchronously() async {
        var values: [Bool] = []
        let monitor = PowerStateMonitor { values.append($0) }
        monitor.start()
        defer { monitor.stop() }
        #expect(values.count == 1)
    }
}

/// `ProcessInfo` exposes the inputs we care about as instance properties, so a
/// subclass is enough to feed deterministic values into `shouldPause`.
private final class FakeProcessInfo: ProcessInfo, @unchecked Sendable {
    private let low: Bool
    private let thermal: ProcessInfo.ThermalState

    init(low: Bool, thermal: ProcessInfo.ThermalState) {
        self.low = low
        self.thermal = thermal
        super.init()
    }

    override var isLowPowerModeEnabled: Bool { low }
    override var thermalState: ProcessInfo.ThermalState { thermal }
}
