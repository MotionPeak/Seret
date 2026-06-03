import DebridCore

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
}
