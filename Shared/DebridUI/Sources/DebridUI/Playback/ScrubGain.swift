import Foundation

/// Maps a horizontal trackpad displacement to a scrub delta in seconds.
///
/// The mapping is **relative** (displacement from where the thumb landed), never absolute
/// finger-x → film-position: on a trackpad the viewer cannot see where their finger is, so an
/// absolute mapping is unusable. It is also **non-linear** — a linear map that reaches the end of
/// a 2-hour film across the surface makes every small movement jump ~15 seconds, which is the
/// "clumsy" feel. Here the linear term keeps small movements fine-grained and a cubic term takes
/// over for large sweeps.
///
/// Pure and `Double`-based so the feel is unit-tested without a remote.
public enum ScrubGain {

    /// Usable half-width of the Siri Remote touch surface in the gesture recognizer's points.
    /// A gesture starts wherever the thumb lands, so the reachable displacement in one direction
    /// is about half the surface.
    public static let halfSurface: Double = 500

    /// Seconds covered by the fine (linear) term at full deflection. Below this the response is
    /// effectively linear and precise.
    public static let fineSpan: Double = 30

    /// How much of the film one full sweep covers. Was half, which is what made even a calmed curve
    /// feel hot: half a 2-hour film across one thumb travel means the *whole* mapping is steep, and
    /// no exponent fixes that because the linear term scales with it too. A quarter still reaches
    /// 30 minutes in one sweep — far more than aiming ever needs — and you can always sweep twice.
    public static let sweepFraction: Double = 0.25

    /// How sharply the coarse term ramps. This is THE sensitivity knob.
    ///
    /// It was 3, which put the cubic term in charge far too early: on a 2-hour film a 100pt nudge
    /// jumped 40s and 150pt jumped nearly two minutes, so ordinary thumb movement overshot whatever
    /// you were aiming at — reported as "sensitivity is too high, it skips too much". At 5 the same
    /// movements are ~13s and ~27s, while a full sweep still covers half the film, so reach is
    /// unchanged and only the usable middle gets calmer. Raise it further to soften more.
    public static let coarseExponent: Double = 5

    /// - Parameters:
    ///   - points: horizontal displacement from the gesture's origin, in points. Positive = right.
    ///   - duration: media length in seconds. `0` (not yet reported) falls back to one hour so the
    ///     handle still moves instead of freezing.
    /// - Returns: the signed scrub delta in seconds.
    public static func seconds(forDisplacement points: Double, duration: Double) -> Double {
        guard points != 0 else { return 0 }
        let span = duration > 0 ? duration : 3600
        let normalized = min(1, abs(points) / halfSurface)
        // A full sweep covers `sweepFraction` of the film; `fineSpan` is carved out of that for the
        // linear term so short movements stay precise. Clamped so a very short clip can't invert
        // the curve — on a clip shorter than the fine span the mapping is purely linear.
        let coarseSpan = max(0, span * sweepFraction - fineSpan)
        let magnitude = fineSpan * normalized + coarseSpan * pow(normalized, coarseExponent)
        // Never let the fine term alone overshoot half of a very short clip.
        let capped = min(magnitude, span / 2)
        return points > 0 ? capped : -capped
    }
}
