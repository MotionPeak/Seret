import Foundation

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
        } catch let HTTPError.status(400, _) {
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
}
