import Foundation

public enum TraktAuthError: Error, Equatable, Sendable {
    case deviceCodeExpired
    case deniedOrUsed
}

public struct TraktClient: Sendable {
    public static let base = URL(string: "https://api.trakt.tv")!

    let clientID: String
    private let clientSecret: String
    private let http: HTTPClient
    /// Provides the current access token for authed calls; nil for the auth calls themselves.
    private let token: (@Sendable () async throws -> String)?

    public init(clientID: String, clientSecret: String, http: HTTPClient = HTTPClient(),
                token: (@Sendable () async throws -> String)? = nil) {
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.http = http
        self.token = token
    }

    // MARK: Headers

    private var baseHeaders: [String: String] {
        ["Content-Type": "application/json",
         "trakt-api-version": "2",
         "trakt-api-key": clientID]
    }

    func authedHeaders() async throws -> [String: String] {
        var h = baseHeaders
        if let token { h["Authorization"] = "Bearer \(try await token())" }
        return h
    }

    // MARK: Device-code auth

    private struct DeviceCodeRequest: Encodable { let client_id: String }
    private struct PollRequest: Encodable { let code: String; let client_id: String; let client_secret: String }
    private struct RefreshRequest: Encodable {
        let refresh_token: String; let client_id: String; let client_secret: String
        let redirect_uri: String; let grant_type: String
    }

    public func startDeviceCode() async throws -> TraktDeviceCode {
        try await http.post(Self.base.appending(path: "oauth/device/code"),
                            json: DeviceCodeRequest(client_id: clientID), headers: baseHeaders)
    }

    /// One poll attempt: token once authorized, `nil` while pending. Throws on expiry/denial.
    public func pollToken(deviceCode: String) async throws -> TraktToken? {
        do {
            return try await http.post(Self.base.appending(path: "oauth/device/token"),
                                       json: PollRequest(code: deviceCode, client_id: clientID,
                                                         client_secret: clientSecret),
                                       headers: baseHeaders)
        } catch let HTTPError.status(code, _) {
            switch code {
            case 400: return nil                        // authorization_pending
            case 410: throw TraktAuthError.deviceCodeExpired
            case 409, 418: throw TraktAuthError.deniedOrUsed
            case 429: return nil                        // slow down — treated as pending
            default: throw HTTPError.status(code: code, body: "")
            }
        }
    }

    public func awaitToken(
        for code: TraktDeviceCode,
        sleep: @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) async throws -> TraktToken {
        var remaining = code.expiresIn
        while remaining > 0 {
            if let token = try await pollToken(deviceCode: code.deviceCode) { return token }
            try await sleep(.seconds(code.interval))
            remaining -= code.interval
        }
        throw TraktAuthError.deviceCodeExpired
    }

    public func refresh(_ token: TraktToken) async throws -> TraktToken {
        try await http.post(Self.base.appending(path: "oauth/token"),
                            json: RefreshRequest(refresh_token: token.refreshToken,
                                                 client_id: clientID, client_secret: clientSecret,
                                                 redirect_uri: "urn:ietf:wg:oauth:2.0:oob",
                                                 grant_type: "refresh_token"),
                            headers: baseHeaders)
    }
}
