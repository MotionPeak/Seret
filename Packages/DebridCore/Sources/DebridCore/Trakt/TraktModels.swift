import Foundation

public struct TraktDeviceCode: Decodable, Sendable, Equatable {
    public let deviceCode: String
    public let userCode: String
    public let verificationURL: String
    public let expiresIn: Int
    public let interval: Int

    public init(deviceCode: String, userCode: String, verificationURL: String,
                expiresIn: Int, interval: Int) {
        self.deviceCode = deviceCode
        self.userCode = userCode
        self.verificationURL = verificationURL
        self.expiresIn = expiresIn
        self.interval = interval
    }

    enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case verificationURL = "verification_url"
        case expiresIn = "expires_in"
        case interval
    }
}

public struct TraktToken: Codable, Sendable, Equatable {
    public let accessToken: String
    public let refreshToken: String
    public let expiresIn: Int
    public let createdAt: Int
    public let tokenType: String
    public let scope: String

    public init(accessToken: String, refreshToken: String, expiresIn: Int,
                createdAt: Int, tokenType: String, scope: String) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresIn = expiresIn
        self.createdAt = createdAt
        self.tokenType = tokenType
        self.scope = scope
    }

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case createdAt = "created_at"
        case tokenType = "token_type"
        case scope
    }
}
