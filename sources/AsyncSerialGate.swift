import Foundation

/// A FIFO async mutex confined to the main actor. Only one critical section runs
/// at a time; overlapping callers queue and resume in arrival order.
///
/// Because it is `@MainActor`, its own bookkeeping needs no locking. A caller
/// whose task is cancelled while still queued is dropped from the queue and its
/// `run` returns `nil` (it never entered the critical section), so cancellation
/// can never deadlock the queue.
@MainActor
final class AsyncSerialGate {
    private var locked = false
    private var waiters: [(id: UUID, continuation: CheckedContinuation<Bool, Never>)] = []

    /// Run `operation` exclusively. Returns its result, or `nil` if the calling
    /// task was cancelled before it acquired the gate (operation not run).
    func run<T: Sendable>(_ operation: () async -> T) async -> T? {
        guard await acquire() else { return nil }
        defer { release() }
        return await operation()
    }

    private func acquire() async -> Bool {
        if Task.isCancelled { return false }
        if !locked {
            locked = true
            return true
        }

        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                waiters.append((id: id, continuation: continuation))
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.dropWaiter(id) }
        }
    }

    private func release() {
        if waiters.isEmpty {
            locked = false
        } else {
            // Hand the baton straight to the next waiter; `locked` stays true.
            let next = waiters.removeFirst()
            next.continuation.resume(returning: true)
        }
    }

    private func dropWaiter(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        let waiter = waiters.remove(at: index)
        waiter.continuation.resume(returning: false)
    }
}
