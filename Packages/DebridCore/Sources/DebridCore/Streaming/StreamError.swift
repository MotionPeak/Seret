import Foundation

/// What a stream session can fail with.
public enum StreamError: Error, Equatable, Sendable {
    /// RD answered with this non-success status (after one link refresh, for 403/404/410).
    case upstreamStatus(Int)
    /// RD gave no usable answer: the connection failed without a status, or RD sent the whole
    /// file in answer to a range.
    case transport(String)
    /// A read at or past the end of the file.
    case endOfFile
    /// The session was closed while the read waited.
    case closed
}

/// Why Real-Debrid is not serving a stream, as the player needs to tell it apart.
///
/// libvlc reports either as a plain end of file, so the player asks. The difference decides what
/// the viewer sees: a refusal is final (Retry would only hear it again), while RD failing for now
/// — the network down, a 5xx, a link refresh that did not get through — is a reason to reopen at
/// the playhead, never "Real-Debrid stopped sending this file".
public enum UpstreamFailure: Error, Equatable, Sendable {
    /// RD said no for good: a 4xx no fresh link fixed, or a range it keeps ignoring.
    case refused(StreamError)
    /// RD is failing right now; the next attempt may well work.
    case unavailable(StreamError)
}
