import Foundation

/// Everything needed to make and refresh authenticated RD calls.
/// A `isStatic` credential is a personal API token (no refresh, no device creds).
public struct StoredCredentials: Codable, Sendable, Equatable {
    public let token: RDToken
    public let deviceCredentials: RDDeviceCredentials
    public let obtainedAt: Date
    public let isStatic: Bool

    public init(token: RDToken, deviceCredentials: RDDeviceCredentials,
                obtainedAt: Date, isStatic: Bool = false) {
        self.token = token
        self.deviceCredentials = deviceCredentials
        self.obtainedAt = obtainedAt
        self.isStatic = isStatic
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        token = try c.decode(RDToken.self, forKey: .token)
        deviceCredentials = try c.decode(RDDeviceCredentials.self, forKey: .deviceCredentials)
        obtainedAt = try c.decode(Date.self, forKey: .obtainedAt)
        isStatic = try c.decodeIfPresent(Bool.self, forKey: .isStatic) ?? false
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
