import Foundation
import DebridCore

/// Thrown when a pasted personal API token is rejected by Real-Debrid.
enum TokenSignInError: Error, Equatable { case invalidToken }

/// The two device-code steps the sign-in model depends on, so its phase machine
/// is unit-testable without the network. `LiveAuthFlow` is the real implementation;
/// tests use a `FakeAuthFlow`. All RD/networking lives in `DebridCore` (the brain) —
/// this is thin glue only.
@MainActor
protocol AuthFlow {
    /// Start the device-code flow → the user-facing code + verification URL.
    func begin() async throws -> RDDeviceCode
    /// Wait for the user to authorize, then mint + persist tokens. One long await.
    func awaitSignIn(_ code: RDDeviceCode) async throws
    /// Validate + persist a personal API token (real-debrid.com/apitoken). No device-code dance.
    func signIn(token: String) async throws
}

@MainActor
struct LiveAuthFlow: AuthFlow {
    let auth: RealDebridAuthClient
    let session: RealDebridSession

    func begin() async throws -> RDDeviceCode {
        try await auth.startDeviceCode()
    }

    func awaitSignIn(_ code: RDDeviceCode) async throws {
        let credentials = try await auth.awaitCredentials(for: code)
        let token = try await auth.requestToken(deviceCode: code.deviceCode, credentials: credentials)
        try await session.establish(token: token, deviceCredentials: credentials)
    }

    func signIn(token: String) async throws {
        guard try await auth.validateToken(token) else { throw TokenSignInError.invalidToken }
        try await session.establishStaticToken(token)
    }
}

/// TorBox sign-in: the device-code flow plus a pasted API key.
///
/// A class because the poll needs the `TorBoxDeviceCode` (`expiresAt`, `interval`) that the shared
/// `RDDeviceCode` presentation type doesn't carry, so `begin()` keeps it for `awaitSignIn`. The model
/// reuses a still-valid code on retry without calling `begin()` again; the kept code is still there.
///
/// A Free-plan key signs in like any other — the plan warning belongs to Settings. Never logs the key.
@MainActor
final class TorBoxAuthFlow: AuthFlow {
    private let auth: TorBoxAuthClient
    private let session: TorBoxSession
    private let now: () -> Date
    private var pending: TorBoxDeviceCode?

    init(auth: TorBoxAuthClient, session: TorBoxSession, now: @escaping () -> Date = { Date() }) {
        self.auth = auth
        self.session = session
        self.now = now
    }

    func begin() async throws -> RDDeviceCode {
        let code = try await auth.startDeviceCode()
        pending = code
        return code.asDeviceCode(now: now())
    }

    func awaitSignIn(_ code: RDDeviceCode) async throws {
        // Only a code this flow minted can be polled; anything else has nothing to wait on.
        guard let pending, pending.deviceCode == code.deviceCode else { throw TorBoxAuthError.expired }
        let key = try await auth.awaitToken(for: pending)
        try await session.establish(key: key)
        self.pending = nil
    }

    func signIn(token: String) async throws {
        do {
            _ = try await auth.validate(key: token)
        } catch TorBoxAuthError.invalidKey {
            throw TokenSignInError.invalidToken
        }
        try await session.establish(key: token)
    }
}
