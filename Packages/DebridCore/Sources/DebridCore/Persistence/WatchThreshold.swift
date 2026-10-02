import Foundation

/// Where a title stops being "still watching" and starts counting as watched.
///
/// This used to be one number — four fifths of the runtime — which is twenty-five minutes early on
/// a two-hour feature, and that is when the Letterboxd diary entry was filed. The question it
/// should answer is "is the film over", and the end of the last spoken line — or where the credits
/// start, when a timestamp database knows — answers it far better than any fraction.
///
/// Pure, and deliberately here rather than in `PlayerModel` — the player supplies the subtitle cue,
/// but manual marks and the web server have no player and still need the fallback.
public enum WatchThreshold {
    /// The estimate used when nothing says where the film ends, as a fraction of the runtime. On
    /// its own this is ten minutes from the end of a two-hour feature — still inside the film, which
    /// is when the rating prompt used to ask about it — so on a feature `estimatedCreditsSeconds`
    /// pushes it later. It is what keeps the fallback near the end of a SHORT file.
    public static let estimatedFraction = 0.92

    /// How far from the end the estimate sits on a feature: inside the credits of nearly any film
    /// (a feature's roll runs five to twelve minutes). Late is the side to err on — a prompt during
    /// the credits is harmless, one during the last scene asks for an opinion the viewer has not
    /// formed yet.
    public static let estimatedCreditsSeconds: Double = 300

    /// Evidence of where the film ends — a last subtitle cue, a credits timestamp — landing before
    /// this much of the runtime is partial, mistimed or for another cut, not evidence.
    public static let plausibleCueFraction = 0.8

    /// Kept clear of the final frame, so subtitles that caption the credits cannot push the
    /// threshold past the point a viewer actually stops watching.
    static let tailSeconds: Double = 30

    /// The second past which this title counts as watched, or nil when nobody measured the runtime.
    ///
    /// - Parameters:
    ///   - lastSubtitleCue: end of the last spoken line, when a subtitle is known.
    ///   - creditsStart: where the credits begin, when a timestamp database knows.
    ///
    /// With both, the LATER wins: the credits can only start after the last line, and a final scene
    /// with no dialogue is exactly the case where the last line is too early.
    public static func finishedAt(duration: Double, lastSubtitleCue: Double?,
                                  creditsStart: Double? = nil) -> Double? {
        guard duration > 0 else { return nil }
        let estimate = max(estimatedFraction * duration, duration - estimatedCreditsSeconds)

        let evidence = [lastSubtitleCue, creditsStart].compactMap { $0 }
            .filter { $0 >= plausibleCueFraction * duration }
        guard let end = evidence.max() else { return estimate }
        // `max` with the estimate matters on a short file, where the thirty-second tail is a
        // bigger slice than the fraction and subtracting it alone would move the threshold
        // EARLIER than having no evidence at all.
        return min(end, max(estimatedFraction * duration, duration - tailSeconds))
    }

    /// Whether a playhead has crossed into "watched".
    public static func hasReachedEnd(position: Double, duration: Double,
                                     lastSubtitleCue: Double?, creditsStart: Double? = nil) -> Bool {
        guard let at = finishedAt(duration: duration, lastSubtitleCue: lastSubtitleCue,
                                  creditsStart: creditsStart)
        else { return false }
        return position >= at
    }
}
