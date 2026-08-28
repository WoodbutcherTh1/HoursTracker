import Foundation

/// Serializes CloudKit write tasks so uploads/deletes cannot interleave out of order.
///
/// Implementation note: simply `await`ing `work()` inside the actor body is NOT
/// enough — Swift actors are reentrant, so every suspension point inside
/// `work()` would let the next enqueued task start running concurrently. The
/// queue therefore chains each job onto the previous one via an explicit
/// `Task` linked list: a job starts only after its predecessor finishes.
actor CloudWriteQueue {
    private var tail: Task<Void, Never>?

    func enqueue(_ work: @escaping @Sendable () async -> Void) async {
        let task = Task { [previous = tail] in
            await previous?.value
            await work()
        }
        tail = task
        await task.value
    }

    func enqueueThrowing(_ work: @escaping @Sendable () async throws -> Void) async throws {
        // Run through the same chain as non-throwing jobs so ordering is
        // shared across both entry points. Errors propagate to this caller
        // only; the chain itself always continues.
        let box = ThrowingJob(work: work)
        await enqueue { await box.run() }
        try box.rethrowIfFailed()
    }

    func waitForPendingWork() async {
        await tail?.value
    }
}

/// Bridges a throwing closure through the non-throwing chain, capturing the
/// error so it can be rethrown to the original caller.
private final class ThrowingJob: @unchecked Sendable {
    private let work: @Sendable () async throws -> Void
    private var error: Error?

    init(work: @escaping @Sendable () async throws -> Void) {
        self.work = work
    }

    func run() async {
        do {
            try await work()
        } catch {
            self.error = error
        }
    }

    func rethrowIfFailed() throws {
        if let error { throw error }
    }
}
