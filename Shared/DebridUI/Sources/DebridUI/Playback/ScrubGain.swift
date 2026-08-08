import Foundation

/// Maps a horizontal trackpad displacement to a scrub delta in seconds.
///
/// The mapping is **relative** (displacement from where the thumb landed), never absolute
/// finger-x → film-position: on a trackpad the viewer cannot see where their finger is, so an
/// absolute mapping is unusable.
///
/// Two properties matter more than the exact curve, and both were learned the hard way on a real
/// Apple TV:
///
/// **It never stops.** The previous mapping clamped displacement at 500pt, which is about half of
/// what the Siri Remote actually delivers in one thumb sweep — so the outer half of the pad was
/// dead, and the viewer hit an invisible wall mid-gesture ("it cuts off and doesn't let me do more
/// than that"). Past the nominal reach the curve here continues at its terminal slope, so the only
/// limit is the physical edge of the surface, and lifting to re-swipe carries on from there.
///
/// **It means the same thing on every title.** Reach used to be a FRACTION of the film, so one
/// sweep was 30 minutes on a 2-hour film and 5 on a short episode. The viewer could never build a
/// reflex. Both terms here are absolute, so a given thumb movement is a given number of seconds
/// whatever is playing.
///
/// Precision is the goal; long-distance travel has its own affordance (hold left/right to scan).
///
/// Pure and `Double`-based so the feel is unit-tested without a remote.
public enum ScrubGain {

    /// The fine term: a flat, predictable rate that owns short movements. 100pt ≈ 4s.
    public static let fineRate: Double = 0.04

    /// The coarse term's span at full pad travel, in seconds — **absolute**, not a share of the
    /// film. Four minutes is far more than aiming ever needs, and the scan handles the rest.
    public static let coarseSpan: Double = 240

    /// Nominal full travel of the touch surface in the gesture recogniser's points. This sets where
    /// the coarse term reaches `coarseSpan`; it is NOT a clamp, so an underestimate costs nothing
    /// but a slightly earlier switch to the linear continuation.
    public static let reach: Double = 700

    /// How sharply the coarse term ramps. Was 5, which made the curve flat then explosive right
    /// where aiming happens — 250pt threw 70s and 500pt threw thirty minutes. At 3 the same
    /// movements are 21s and 1:47.
    public static let coarseExponent: Double = 3

    /// - Parameters:
    ///   - points: horizontal displacement from the gesture's origin, in points. Positive = right.
    ///   - duration: media length in seconds, used only to stop a short clip being thrown further
    ///     than it is long. `0` (not yet reported) imposes no cap, so the handle still moves.
    /// - Returns: the signed scrub delta in seconds.
    public static func seconds(forDisplacement points: Double, duration: Double) -> Double {
        guard points != 0 else { return 0 }
        let travel = abs(points)
        let normalized = travel / reach
        // Within the pad the coarse term is a gentle cubic. PAST it the cubic is continued at its
        // terminal SLOPE rather than as a cubic: a continued cubic would double its span every
        // fraction beyond reach (2x travel would jump half an hour), which is the "too sensitive"
        // complaint reintroduced at the far end. The linear continuation is C1-continuous, so
        // there is no seam to feel where the two segments meet.
        let coarse = normalized <= 1
            ? pow(normalized, coarseExponent)
            : 1 + coarseExponent * (normalized - 1)
        let magnitude = fineRate * travel + coarseSpan * coarse
        // The one place duration still matters: never throw a clip further than half its length.
        let capped = duration > 0 ? min(magnitude, duration / 2) : magnitude
        return points > 0 ? capped : -capped
    }
}
