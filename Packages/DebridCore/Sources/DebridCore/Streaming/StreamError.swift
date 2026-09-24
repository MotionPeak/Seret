import Foundation

/// What a stream session can fail with.
public enum StreamError: Error, Equatable, Sendable {
    /// RD answered with this non-success status (after one link refresh, for 403/404/410).
    case upstreamStatus(Int)
    /// The connection to RD failed without a status.
    case transport(String)
    /// A read at or past the end of the file.
    case endOfFile
    /// The session was closed while the read waited.
    case closed
}
