import Foundation

/// Whether an error is a debrid account's request limit, whichever provider raised it.
public enum DebridRateLimit {
    public static func matches(_ error: Error) -> Bool {
        switch error {
        case RDAddError.rateLimited, TorBoxError.rateLimited, HTTPError.status(code: 429, body: _):
            return true
        default:
            return false
        }
    }
}
