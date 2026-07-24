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
    public static let fineSpan: Double = 60

    /// - Parameters:
    ///   - points: horizontal displacement from the gesture's origin, in points. Positive = right.
    ///   - duration: media length in seconds. `0` (not yet reported) falls back to one hour so the
    ///     handle still moves instead of freezing.
    /// - Returns: the signed scrub delta in seconds.
    public static func seconds(forDisplacement points: Double, duration: Double) -> Double {
        guard points != 0 else { return 0 }
        let span = duration > 0 ? duration : 3600
        let normalized = min(1, abs(points) / halfSurface)
        // A full sweep covers half the film; `fineSpan` is carved out of that for the linear term
        // so short movements stay precise. Clamped so a very short clip can't invert the curve.
        let coarseSpan = max(0, span / 2 - fineSpan)
        let magnitude = fineSpan * normalized + coarseSpan * pow(normalized, 3)
        // Never let the fine term alone overshoot half of a very short clip.
        let capped = min(magnitude, span / 2)
        return points > 0 ? capped : -capped
    }
}
