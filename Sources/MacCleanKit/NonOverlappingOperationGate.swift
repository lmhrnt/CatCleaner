import Foundation

/// Thread-safe gate that allows at most one in-flight operation per key.
///
/// This is intentionally synchronous so it can be used from timeout wrappers
/// whose underlying work may continue after the caller stops waiting.
public final class NonOverlappingOperationGate<Key: Hashable & Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var activeKeys: Set<Key> = []

    public init() {}

    /// Returns `true` when the caller acquired the key. A second caller using
    /// the same key receives `false` until `end(_:)` releases it.
    @discardableResult
    public func begin(_ key: Key) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return activeKeys.insert(key).inserted
    }

    /// Releases a previously acquired key. Calling `end(_:)` for an inactive
    /// key is harmless.
    public func end(_ key: Key) {
        lock.lock()
        activeKeys.remove(key)
        lock.unlock()
    }
}
