import Foundation

/// Decides when the system Now Playing entry genuinely needs rewriting.
///
/// `PlayerModel.tick()` pushes on every VLCKit time event — several times a second — and each push
/// is a cross-process write that makes MediaPlayer re-encode the poster JPEG
/// (`-[MPMediaItemArtwork jpegDataWithSize:]`). On a 2017 Apple TV that is real work to repeat four
/// times a second for no gain: the system EXTRAPOLATES the playhead from elapsed-time + rate, so it
/// only needs telling when that extrapolation would be wrong.
///
/// Deliberately platform-free (no MediaPlayer import) so it compiles on macOS and `swift test` can
/// cover it — `NowPlayingCenter` itself cannot, which is why the decision lives here rather than
/// inline in it.
struct NowPlayingThrottle {
    /// Refresh at least this often even when nothing changed, so our clock and VLCKit's can never
    /// drift apart unnoticed.
    var heartbeat: Double = 5
    /// How far the real playhead may sit from the system's prediction before it is worth correcting.
    /// Comfortably wider than a tick's jitter, far narrower than any deliberate skip.
    var tolerance: Double = 2

    /// State as of the last PUSH — never the last observation. Measuring drift from the last push
    /// is what lets a slow creep accumulate past the tolerance instead of being forgiven each tick.
    private var pushed: (identity: String, position: Double, rate: Double, at: Double)?

    /// Spelled out because the private stored property above makes the memberwise init private.
    init(heartbeat: Double = 5, tolerance: Double = 2) {
        self.heartbeat = heartbeat
        self.tolerance = tolerance
    }

    /// Whether this update has to reach the system. `identity` bundles everything about the entry
    /// that isn't the playhead (title, show, duration), so a new title or episode always pushes.
    mutating func shouldPush(identity: String, position: Double, rate: Double, now: Double) -> Bool {
        guard let last = pushed else { return record(identity, position, rate, now) }
        guard last.identity == identity else { return record(identity, position, rate, now) }
        guard last.rate == rate else { return record(identity, position, rate, now) }
        // Where the system currently believes the playhead is.
        let predicted = last.position + (now - last.at) * last.rate
        guard abs(position - predicted) <= tolerance else {
            return record(identity, position, rate, now)
        }
        guard now - last.at < heartbeat else { return record(identity, position, rate, now) }
        return false
    }

    /// Forget the pushed state, so the next update refreshes the entry unconditionally.
    mutating func reset() { pushed = nil }

    private mutating func record(_ identity: String, _ position: Double,
                                 _ rate: Double, _ now: Double) -> Bool {
        pushed = (identity, position, rate, now)
        return true
    }
}
