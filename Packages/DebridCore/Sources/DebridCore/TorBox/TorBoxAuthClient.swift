import Foundation

public enum TorBoxAuthError: Error, Equatable, Sendable {
    /// TorBox refused the key.
    case invalidKey
    /// The device code ran out before the viewer approved it.
    case expired
}

/// A pending TorBox device-code sign-in.
public struct TorBoxDeviceCode: Sendable, Equatable {
    public let deviceCode: String
    public let code: String
    public let verificationURL: String
    public let friendlyVerificationURL: String
    public let interval: Int
    public let expiresAt: Date

    public init(deviceCode: String, code: String, verificationURL: String, friendlyVerificationURL: String,
                interval: Int, expiresAt: Date) {
        self.deviceCode = deviceCode
        self.code = code
        self.verificationURL = verificationURL
        self.friendlyVerificationURL = friendlyVerificationURL
        self.interval = interval
        self.expiresAt = expiresAt
    }

    /// Presents the code through the sign-in UI built for Real-Debrid.
    public func asDeviceCode(now: Date) -> RDDeviceCode {
        RDDeviceCode(deviceCode: deviceCode, userCode: code, interval: interval,
                     expiresIn: max(0, Int(expiresAt.timeIntervalSince(now))),
                     verificationURL: friendlyVerificationURL)
    }
}

/// TorBox sign-in: the device-code flow (no key involved until it succeeds) and key validation.
/// Both reuse `TorBoxClient`'s envelope decoding and error mapping.
public struct TorBoxAuthClient: Sendable {
    /// The name TorBox shows when the viewer approves the code.
    static let appName = "Seret"

    private let http: HTTPClient

    public init(http: HTTPClient = HTTPClient()) {
        self.http = http
    }

    public func startDeviceCode() async throws -> TorBoxDeviceCode {
        let url = TorBoxClient.url("api/user/auth/device/start", query: [.init(name: "app", value: Self.appName)])
        let wire: StartWire? = try await TorBoxClient.run { try await http.data(url) }
        guard let wire else {
            throw TorBoxError.api(code: "NO_DATA", detail: "TorBox returned no device code.", status: 502)
        }
        guard let expiresAt = ISO8601Timestamp.date(from: wire.expiresAt) else {
            throw HTTPError.decoding("Unparseable expires_at in the device-code response.")
        }
        return TorBoxDeviceCode(deviceCode: wire.deviceCode, code: wire.code, verificationURL: wire.verificationUrl,
                                friendlyVerificationURL: wire.friendlyVerificationUrl, interval: wire.interval,
                                expiresAt: expiresAt)
    }

    /// Polls until the viewer approves the code and returns the account key. The cadence lives
    /// here so the UI just awaits; `sleep` is injectable for instant tests and, in production,
    /// `Task.sleep` keeps the wait cancellable.
    public func awaitToken(
        for code: TorBoxDeviceCode,
        now: @Sendable () -> Date = Date.init,
        sleep: @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) async throws -> String {
        let interval = max(1, code.interval)
        while true {
            if let key = try await pollToken(deviceCode: code.deviceCode) { return key }
            guard now() < code.expiresAt else { throw TorBoxAuthError.expired }
            try await sleep(.seconds(interval))
        }
    }

    /// Checks the key against `/user/me`. A refused key is `.invalidKey`; any other failure
    /// (rate limit, transport) passes through unchanged so the caller doesn't misreport it.
    public func validate(key: String) async throws -> TorBoxUser {
        do {
            return try await TorBoxClient(http: http, tokens: StaticKey(key)).user()
        } catch let error as TorBoxError where error.isAuthRejection {
            throw TorBoxAuthError.invalidKey
        }
    }

    // MARK: - Private

    /// nil while the viewer hasn't approved yet. TorBox reports "pending" as `ITEM_NOT_FOUND`
    /// (observed live) and documents `DEVICE_CODE_NOT_USED` for the same state; both keep waiting,
    /// and `expiresAt` bounds the loop either way.
    private func pollToken(deviceCode: String) async throws -> String? {
        let url = TorBoxClient.url("api/user/auth/device/token", query: [])
        do {
            let wire: TokenWire? = try await TorBoxClient.run {
                try await http.postJSONData(url, json: TokenRequest(deviceCode: deviceCode))
            }
            guard let key = wire?.accessToken, !key.isEmpty else {
                throw TorBoxError.api(code: "NO_DATA", detail: "TorBox returned no token.", status: 502)
            }
            return key
        } catch let TorBoxError.api(code, _, _) where Self.pendingCodes.contains(code) {
            return nil
        }
    }

    private static let pendingCodes: Set<String> = ["ITEM_NOT_FOUND", "DEVICE_CODE_NOT_USED"]

    private struct StaticKey: AccessTokenProviding {
        let key: String
        init(_ key: String) { self.key = key }
        func validAccessToken() async throws -> String { key }
    }

    private struct TokenRequest: Encodable {
        let deviceCode: String
        enum CodingKeys: String, CodingKey { case deviceCode = "device_code" }
    }

    // Decoded with `.convertFromSnakeCase`.
    private struct StartWire: Decodable {
        let deviceCode: String
        let code: String
        let verificationUrl: String
        let friendlyVerificationUrl: String
        let interval: Int
        let expiresAt: String
    }

    private struct TokenWire: Decodable {
        let accessToken: String
    }
}
