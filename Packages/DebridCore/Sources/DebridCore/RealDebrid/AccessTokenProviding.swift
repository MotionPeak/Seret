import Foundation

/// Supplies a currently-valid Real-Debrid access token. `RealDebridSession` conforms;
/// tests use a stub. Keeps resource clients decoupled from Keychain/refresh details.
public protocol AccessTokenProviding: Sendable {
    func validAccessToken() async throws -> String
}

extension RealDebridSession: AccessTokenProviding {}
