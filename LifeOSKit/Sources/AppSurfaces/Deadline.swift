import Foundation
import Synchronization

/// The operation's answer if it arrives within `limit`, else nil, without
/// waiting for an operation that ignores cancellation (a location fix does).
public func firstValue<T: Sendable>(within limit: Duration,
                                    _ operation: @escaping @Sendable () async -> T?) async -> T? {
    await withCheckedContinuation { (continuation: CheckedContinuation<T?, Never>) in
        let once = ResumeOnce(continuation)
        let work = Task { once.resume(await operation()) }
        Task {
            try? await Task.sleep(for: limit)
            work.cancel()
            once.resume(nil)
        }
    }
}

private final class ResumeOnce<T: Sendable>: Sendable {
    private let continuation: Mutex<CheckedContinuation<T?, Never>?>
    init(_ continuation: CheckedContinuation<T?, Never>) { self.continuation = Mutex(continuation) }
    func resume(_ value: T?) {
        continuation.withLock { c in c?.resume(returning: value); c = nil }
    }
}
