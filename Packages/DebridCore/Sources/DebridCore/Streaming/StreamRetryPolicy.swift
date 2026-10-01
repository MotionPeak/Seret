import Foundation

/// How a stream session rides out Real-Debrid failing for a while — Wi-Fi dropping, RD answering
/// 503 or 429: ask again after a growing pause, and give a read up only once RD has failed it for
/// `budget`. Nothing here ever shuts the session: the network coming back must find it still
/// asking.
struct StreamRetryPolicy: Sendable, Equatable {
    /// The pause after the first failure in a row. It doubles with each further one, up to
    /// `maxDelay` — so a drop of a few seconds costs a retry or two, not a burst of them.
    var firstDelay: Duration
    var maxDelay: Duration
    /// How long one read keeps asking an RD that keeps failing before it gives up. Giving up
    /// closes libvlc's connection, and libvlc asks again on a new one — which starts its own.
    var budget: Duration
    /// Whole files answered to range requests in a row before the session stops asking. One bad
    /// server may pass; RD ignoring the range for this file every time will not, and the whole
    /// file is not the bytes that were asked for.
    var wholeFileAnswers: Int

    static let standard = StreamRetryPolicy(firstDelay: .milliseconds(500), maxDelay: .seconds(5),
                                            budget: .seconds(60), wholeFileAnswers: 3)

    /// The pause before asking again after `failures` failures in a row.
    func delay(afterFailures failures: Int) -> Duration {
        guard failures > 0 else { return .zero }
        var delay = firstDelay
        for _ in 1..<failures where delay < maxDelay { delay *= 2 }
        return min(delay, maxDelay)
    }
}
