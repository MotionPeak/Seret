import Foundation

public enum TorBoxError: Error, Equatable, Sendable {
    /// TorBox answered `success: false` (or a non-2xx) with an error code and a human detail.
    case api(code: String, detail: String, status: Int)
    /// HTTP 429. TorBox locks the key out for about 300 s, so callers must not retry.
    case rateLimited(retryAfter: Int?)
    case notSignedIn

    /// The key itself was refused — signing out is the right response.
    public var isAuthRejection: Bool {
        guard case .api(let code, _, _) = self else { return false }
        return ["BAD_TOKEN", "NO_AUTH", "AUTH_ERROR"].contains(code)
    }

    /// The key is valid but the account is on the Free plan, which has no API access. This is NOT
    /// an authentication failure: the viewer stays signed in.
    public var isPlanRestricted: Bool {
        guard case .api(let code, _, _) = self else { return false }
        return code == "PLAN_RESTRICTED_FEATURE"
    }

    public var userMessage: String {
        switch self {
        case .rateLimited:
            return "TorBox is busy — try again in a few minutes."
        case .notSignedIn:
            return "Sign in to TorBox first."
        case .api(_, let detail, _):
            return isPlanRestricted ? "TorBox's API needs a paid plan." : detail
        }
    }
}
