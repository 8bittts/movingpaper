import Foundation
import Testing
@testable import MovingPaper

@MainActor
struct AsyncSerialGateTests {

    @Test func serializesOverlappingOperationsInFIFOOrder() async {
        let gate = AsyncSerialGate()
        var events: [String] = []

        func op(_ tag: String) async {
            _ = await gate.run { () -> Bool in
                events.append("\(tag)-start")
                // Yields would let another task interleave if not serialized.
                await Task.yield()
                await Task.yield()
                events.append("\(tag)-end")
                return true
            }
        }

        // Start `a`, wait until it has entered the critical section, then start
        // `b` so it must queue behind `a`.
        let a = Task { @MainActor in await op("a") }
        while !events.contains("a-start") { await Task.yield() }
        let b = Task { @MainActor in await op("b") }
        _ = await a.value
        _ = await b.value

        #expect(events == ["a-start", "a-end", "b-start", "b-end"])
    }

    @Test func cancelledWaiterReturnsNilAndDoesNotBlockTheQueue() async {
        let gate = AsyncSerialGate()
        var holderContinuation: CheckedContinuation<Void, Never>?

        // Holder acquires the gate and parks until we release it.
        let holder = Task { @MainActor in
            await gate.run { () -> Bool in
                await withCheckedContinuation { holderContinuation = $0 }
                return true
            }
        }
        while holderContinuation == nil { await Task.yield() }

        // Waiter queues behind the holder, then is cancelled while queued.
        let waiter = Task { @MainActor in
            await gate.run { () -> Bool in true }
        }
        await Task.yield()
        waiter.cancel()
        let waiterResult = await waiter.value
        #expect(waiterResult == nil) // never entered the critical section

        // Releasing the holder must leave the gate usable.
        holderContinuation?.resume()
        _ = await holder.value
        let after = await gate.run { () -> Bool in true }
        #expect(after == true)
    }
}
