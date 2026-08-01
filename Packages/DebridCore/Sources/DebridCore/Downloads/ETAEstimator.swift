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

    private let smoothing: Double
    private let staleAfter: TimeInterval
    private let minInterval: TimeInterval

    /// - Parameters:
    ///   - smoothing: weight of the newest observation, 0...1. Higher reacts faster and jitters more.
    ///   - staleAfter: a gap longer than this means the app was away; prior samples are discarded
    ///     rather than averaged across dead time.
    ///   - minInterval: samples closer together than this do not replace the anchor, keeping the
    ///     measured interval long enough to be meaningful.
    public init(smoothing: Double = 0.3,
                staleAfter: TimeInterval = 120,
                minInterval: TimeInterval = 1) {
        self.smoothing = smoothing
        self.staleAfter = staleAfter
        self.minInterval = minInterval
    }

    /// Record a progress sample and return the estimated seconds remaining, or nil when unknown.
    public mutating func observe(fraction: Double, totalBytes: Int,
                                 reportedSpeed: Int?, at now: Date) -> TimeInterval? {
        let total = Double(max(0, totalBytes))
        let done = min(max(0, fraction), 1) * total
        let remaining = max(0, total - done)

        if let previous = anchor {
            let elapsed = now.timeIntervalSince(previous.at)
            if elapsed > staleAfter {
                smoothedRate = nil          // the app was away; the old sample says nothing about now
                anchor = Sample(at: now, bytesDone: done)
            } else if elapsed >= minInterval {
                let observed = (done - previous.bytesDone) / elapsed
                if observed > 0 {
                    smoothedRate = smoothedRate.map { smoothing * observed + (1 - smoothing) * $0 }
                        ?? observed
                }
                anchor = Sample(at: now, bytesDone: done)
            }
            // Closer than minInterval: keep the older anchor so the next delta spans a useful window.
        } else {
            anchor = Sample(at: now, bytesDone: done)
        }

        guard remaining > 0 else { return 0 }
        let fallback = reportedSpeed.flatMap { $0 > 0 ? Double($0) : nil }
        guard let rate = smoothedRate ?? fallback, rate > 0 else { return nil }
        return remaining / rate
    }
}
