import Foundation

/// Turns a stream of download-progress samples into a stable remaining-time estimate.
///
/// Real-Debrid's instantaneous `speed` swings hard between polls, so a raw
/// `remaining / speed` flickers between wildly different values every few seconds. This estimator
/// prefers throughput *observed* across polls, smooths it exponentially, and returns nil rather
/// than inventing a number when it cannot know — callers show a qualitative state instead.
///
/// Pure and clock-injected: `observe` takes the current time rather than reading it.
public struct ETAEstimator: Sendable, Equatable {
    private struct Sample: Sendable, Equatable {
        let at: Date
        let bytesDone: Double
    }

    private var anchor: Sample?
    /// Bytes/sec, exponentially smoothed. Nil until a usable observation exists.
    private var smoothedRate: Double?
    /// When the byte count last actually advanced, and how much it had reached — the pair that
    /// tells a stall apart from a download that simply has not started.
    private var lastProgress: Sample?

    private let smoothing: Double
    private let staleAfter: TimeInterval
    private let minInterval: TimeInterval
    private let stalledAfter: TimeInterval

    /// - Parameters:
    ///   - smoothing: weight of the newest observation, 0...1. Higher reacts faster and jitters more.
    ///   - staleAfter: a gap longer than this means the app was away; prior samples are discarded
    ///     rather than averaged across dead time.
    ///   - minInterval: samples closer together than this do not replace the anchor, keeping the
    ///     measured interval long enough to be meaningful.
    ///   - stalledAfter: with no byte advancing for this long, the estimator reports nothing rather
    ///     than an estimate. A zero observation used to be discarded rather than averaged in, so
    ///     whatever rate happened to be positive last lived on forever and a download that had
    ///     stopped kept counting confidently down — the invented number this type promises not to
    ///     produce.
    public init(smoothing: Double = 0.3,
                staleAfter: TimeInterval = 120,
                minInterval: TimeInterval = 1,
                stalledAfter: TimeInterval = 60) {
        self.smoothing = smoothing
        self.staleAfter = staleAfter
        self.minInterval = minInterval
        self.stalledAfter = stalledAfter
    }

    /// Record a progress sample and return the estimated seconds remaining, or nil when unknown.
    public mutating func observe(fraction: Double, totalBytes: Int,
                                 reportedSpeed: Int?, at now: Date) -> TimeInterval? {
        let total = Double(max(0, totalBytes))
        let done = min(max(0, fraction), 1) * total
        let remaining = max(0, total - done)

        if let known = lastProgress, done > known.bytesDone {
            lastProgress = Sample(at: now, bytesDone: done)
        } else if lastProgress == nil {
            lastProgress = Sample(at: now, bytesDone: done)
        }

        if let previous = anchor {
            let elapsed = now.timeIntervalSince(previous.at)
            if elapsed > staleAfter {
                smoothedRate = nil          // the app was away; the old sample says nothing about now
                lastProgress = Sample(at: now, bytesDone: done)   // …and it is not a stall either
                anchor = Sample(at: now, bytesDone: done)
            } else if elapsed >= minInterval {
                // A zero observation is a measurement, not a missing one. Averaging it in is what
                // makes a slowing download read as slowing instead of holding its old estimate.
                let observed = max(0, (done - previous.bytesDone) / elapsed)
                if let current = smoothedRate {
                    smoothedRate = smoothing * observed + (1 - smoothing) * current
                } else if observed > 0 {
                    smoothedRate = observed
                }
                anchor = Sample(at: now, bytesDone: done)
            }
            // Closer than minInterval: keep the older anchor so the next delta spans a useful window.
        } else {
            anchor = Sample(at: now, bytesDone: done)
        }

        guard remaining > 0 else { return 0 }
        let fallback = reportedSpeed.flatMap { $0 > 0 ? Double($0) : nil }
        // Nothing has moved for long enough that any rate we could quote is fiction.
        //
        // Two things are deliberately NOT stalls. A download that has not STARTED — there is simply
        // nothing observed yet, and RD's reported speed is the only signal there is. And one RD
        // still reports a live speed for: `progress` is a percentage, so on a large slow download a
        // single reported step can take minutes while bytes are moving the whole time, and calling
        // that stalled would blank the ETA of a download that is working.
        if let known = lastProgress, known.bytesDone > 0, fallback == nil,
           now.timeIntervalSince(known.at) >= stalledAfter {
            return nil
        }
        guard let rate = smoothedRate ?? fallback, rate > 0 else { return nil }
        return remaining / rate
    }
}
