import Foundation

public enum RealDebridAuthError: Error, Equatable {
    /// The device code's `expiresIn` budget elapsed before the user authorized.
    case deviceCodeExpired
}

/// Real-Debrid OAuth2 device-code flow using the public open-source client id
/// (`X245A4XAIBGVM`) — no client secret required to start. See spec §5.2.
public struct RealDebridAuthClient: Sendable {
    public static let openSourceClientID = "X245A4XAIBGVM"

    private static let base = URL(string: "https://api.real-debrid.com")!
    private static let grantType = "http://oauth.net/grant_type/device/1.0"

    private let http: HTTPClient

    public init(http: HTTPClient = HTTPClient()) {
        self.http = http
    }

    public func startDeviceCode(clientID: String = openSourceClientID) async throws -> RDDeviceCode {
        var comps = URLComponents(
            url: Self.base.appending(path: "/oauth/v2/device/code"),
            resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "new_credentials", value: "yes"),
        ]
        return try await http.get(comps.url!)
    }

    /// One poll attempt. Returns credentials once authorized; `nil` while pending.
    public func pollCredentials(deviceCode: String,
                                clientID: String = openSourceClientID) async throws -> RDDeviceCredentials? {
        var comps = URLComponents(
            url: Self.base.appending(path: "/oauth/v2/device/credentials"),
            resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "code", value: deviceCode),
        ]
        do {
            let credentials: RDDeviceCredentials = try await http.get(comps.url!)
            return credentials
        } catch HTTPError.status(400, _) {
            // authorization_pending — Real-Debrid returns 400 while the user
            // hasn't authorized yet. Any other status (denied / expired / etc.)
            // propagates so the polling loop can stop instead of spinning forever.
            return nil
        }
    }

    public func requestToken(deviceCode: String,
                             credentials: RDDeviceCredentials) async throws -> RDToken {
        try await http.post(
            Self.base.appending(path: "/oauth/v2/token"),
            form: [
                "client_id": credentials.clientID,
                "client_secret": credentials.clientSecret,
                "code": deviceCode,
                "grant_type": Self.grantType,
            ])
    }

    public func refresh(token: RDToken,
                        credentials: RDDeviceCredentials) async throws -> RDToken {
        try await http.post(
            Self.base.appending(path: "/oauth/v2/token"),
            form: [
                "client_id": credentials.clientID,
                "client_secret": credentials.clientSecret,
                "code": token.refreshToken,
                "grant_type": Self.grantType,
            ])
    }

    /// Polls `pollCredentials` on the code's `interval` until the user authorizes
    /// (returns credentials) or the code's `expiresIn` budget is exhausted
    /// (throws `.deviceCodeExpired`). The RD poll **cadence lives here in the brain**
    /// so app UI just `await`s this once. `sleep` is injectable for instant tests;
    /// production uses `Task.sleep`, which makes the wait cancellable.
    public func awaitCredentials(
        for code: RDDeviceCode,
        clientID: String = openSourceClientID,
        sleep: @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) async throws -> RDDeviceCredentials {
        let interval = max(1, code.interval)
        var remaining = code.expiresIn
        while true {
            if let credentials = try await pollCredentials(deviceCode: code.deviceCode,
                                                           clientID: clientID) {
                return credentials
            }
            guard remaining > 0 else { throw RealDebridAuthError.deviceCodeExpired }
            let step = min(interval, remaining)
            try await sleep(.seconds(step))
            remaining -= step
        }
    }
}
