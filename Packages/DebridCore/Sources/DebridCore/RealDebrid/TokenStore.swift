import Foundation

/// Everything needed to make and refresh authenticated RD calls.
public struct StoredCredentials: Codable, Sendable, Equatable {
    public var token: RDToken
    public var deviceCredentials: RDDeviceCredentials
    public var obtainedAt: Date

    public init(token: RDToken, deviceCredentials: RDDeviceCredentials, obtainedAt: Date) {
        self.token = token
        self.deviceCredentials = deviceCredentials
        self.obtainedAt = obtainedAt
    }
}

public protocol TokenStore: Sendable {
    func load() throws -> StoredCredentials?
    func save(_ credentials: StoredCredentials) throws
    func clear() throws
}

/// Test/double implementation. Thread-safe.
public final class InMemoryTokenStore: TokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: StoredCredentials?

    public init() {}

    public func load() throws -> StoredCredentials? {
        lock.lock(); defer { lock.unlock() }
        return stored
    }
    public func save(_ credentials: StoredCredentials) throws {
        lock.lock(); defer { lock.unlock() }
        stored = credentials
    }
    public func clear() throws {
        lock.lock(); defer { lock.unlock() }
        stored = nil
    }
}
