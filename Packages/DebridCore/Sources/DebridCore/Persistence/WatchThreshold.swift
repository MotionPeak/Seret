import Foundation

/// Where a title stops being "still watching" and starts counting as watched.
///
/// This used to be one number — four fifths of the runtime — which is twenty-five minutes early on
/// a two-hour feature, and that is when the Letterboxd diary entry was filed. The question it
/// should answer is "is the film over", and the end of the last spoken line answers it far better
/// than any fraction: from there on, the credits are rolling.
///
/// Pure, and deliberately here rather than in `PlayerModel` — the player supplies the subtitle cue,
/// but manual marks and the web server have no player and still need the fallback.
public enum WatchThreshold {
    /// The estimate used when nothing says where the dialogue ends. ~10 minutes from the end of a
    /// two-hour feature, which is what a viewer means by "when the credits roll".
    public static let estimatedFraction = 0.92

    /// A subtitle file ending before this much of the runtime is partial or mistimed, not evidence
    /// that the film ended there.
    static let plausibleCueFraction = 0.8

    /// Kept clear of the final frame, so subtitles that caption the credits cannot push the
    /// threshold past the point a viewer actually stops watching.
    static let tailSeconds: Double = 30

    /// The second past which this title counts as watched, or nil when nobody measured the runtime.
    ///
    /// - Parameter lastSubtitleCue: end of the last spoken line, when a subtitle is loaded.
    public static func finishedAt(duration: Double, lastSubtitleCue: Double?) -> Double? {
        guard duration > 0 else { return nil }
        let estimate = estimatedFraction * duration

        guard let cue = lastSubtitleCue, cue >= plausibleCueFraction * duration
        else { return estimate }
        // `max` with the estimate matters on a short file, where the thirty-second tail is a
        // bigger slice than the fraction and subtracting it alone would move the threshold
        // EARLIER than having no subtitle at all.
        return min(cue, max(estimate, duration - tailSeconds))
    }

    /// Whether a playhead has crossed into "watched".
    public static func hasReachedEnd(position: Double, duration: Double,
                                     lastSubtitleCue: Double?) -> Bool {
        guard let at = finishedAt(duration: duration, lastSubtitleCue: lastSubtitleCue)
        else { return false }
        return position >= at
    }
}
