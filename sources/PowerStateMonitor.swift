import Foundation

/// Observes Low Power Mode and thermal pressure, calling `onChange` whenever
/// the "should pause" verdict flips. The first call fires synchronously from
/// `start()` so callers can establish initial state without duplicating logic.
@MainActor
final class PowerStateMonitor {
    private var observers: [NSObjectProtocol] = []
    private var lastVerdict: Bool = false
    private let onChange: (Bool) -> Void

    init(onChange: @escaping (Bool) -> Void) {
        self.onChange = onChange
    }

    /// Begin observing. Emits the current verdict immediately.
    func start() {
        let center = NotificationCenter.default

        let lowPower = center.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.evaluate() }
        }

        let thermal = center.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.evaluate() }
        }

        observers = [lowPower, thermal]
        lastVerdict = Self.shouldPause(processInfo: .processInfo)
        onChange(lastVerdict)
    }

    /// Stop observing and release notification registrations.
    func stop() {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
    }

    private func evaluate() {
        let verdict = Self.shouldPause(processInfo: .processInfo)
        guard verdict != lastVerdict else { return }
        lastVerdict = verdict
        Log.power.info("Power verdict changed: shouldPause=\(verdict, privacy: .public)")
        onChange(verdict)
    }

    nonisolated static func shouldPause(processInfo: ProcessInfo) -> Bool {
        if processInfo.isLowPowerModeEnabled { return true }
        switch processInfo.thermalState {
        case .serious, .critical: return true
        case .nominal, .fair: return false
        @unknown default: return false
        }
    }
}
