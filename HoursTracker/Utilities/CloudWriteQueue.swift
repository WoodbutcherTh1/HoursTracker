import Foundation

/// Serializes CloudKit write tasks so uploads/deletes cannot interleave out of order.
actor CloudWriteQueue {
    func enqueue(_ work: @Sendable () async -> Void) async {
        await work()
    }

    func enqueueThrowing(_ work: @Sendable () async throws -> Void) async throws {
        try await work()
    }
}
