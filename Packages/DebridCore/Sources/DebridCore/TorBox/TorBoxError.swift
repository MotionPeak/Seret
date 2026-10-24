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
        case .api(let code, let detail, let status):
            if isPlanRestricted { return "TorBox's API needs a paid plan." }
            let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
            // No detail: a Cloudflare 502/503 answers HTML rather than TorBox's envelope. A blank
            // message left the library error and the sign-in failure empty.
            if (500...599).contains(status) {
                return "TorBox isn't responding right now (HTTP \(status)). Try again in a few minutes."
            }
            // A 200 with `success: false` has no HTTP status worth naming; its code says more.
            return (200..<300).contains(status)
                ? "TorBox returned an error (\(code))."
                : "TorBox returned an error (HTTP \(status))."
        }
    }
}
