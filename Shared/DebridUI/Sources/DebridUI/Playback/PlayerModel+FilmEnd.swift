import Foundation
import DebridCore

extension PlayerModel {

    // MARK: - Where the film ends

    /// How far into a film the player asks where it ends. Late enough that a film abandoned in its
    /// first act spends no subtitle download; early enough that the answer is in long before the
    /// end.
    static let filmEndLookupFraction = 0.5

    /// Halfway into a film, find out where it ends — once.
    ///
    /// The watched line (and with it the Letterboxd rating prompt) is only as good as what the
    /// player knows. A subtitle the viewer downloaded says where the dialogue ends; an EMBEDDED
    /// subtitle, or none, says nothing, and the film fell back to an estimate that asked for a
    /// rating while the last scene was still playing. Films only: the prompt is for films, and an
    /// episode's mark is not worth a download per episode.
    func measureFilmEndIfDue() {
        guard !filmEndMeasured, !isTornDown, episode == nil, duration > 0,
              position >= Self.filmEndLookupFraction * duration else { return }
        filmEndMeasured = true
        let length = duration
        filmEndTask = Task { @MainActor [weak self] in await self?.measureFilmEnd(duration: length) }
    }

    /// The credits timestamp first — free, and the most direct answer — then, only when that is
    /// unknown, a subtitle fetched for nothing but the time of its last line. That subtitle is
    /// never attached: the viewer sees no change, and keeps whatever track they were watching.
    func measureFilmEnd(duration length: Double) async {
        if let credits, let tmdbID = item.tmdbID {
            do {
                creditsStartTime = try await credits.creditsStart(tmdbID: tmdbID, durationSeconds: length)
                note("film end: credits at \(creditsStartTime.map { Timecode.format($0) } ?? "unknown")")
            } catch {
                note("film end: credits lookup failed: \(error)")
            }
        }
        // Credits are later than any line of dialogue, so once they are known a subtitle could
        // only offer an earlier answer. Only a start this file could plausibly have counts.
        let creditsKnown = WatchThreshold.evidence(duration: length, lastSubtitleCue: nil,
                                                   creditsStart: creditsStartTime) != nil
        guard !Task.isCancelled, !isTornDown, !creditsKnown, contentEndTime == nil,
              let subtitles else { return }

        var query = SubtitleQuery.movie(item)
        await resolveMoviehashIfNeeded()
        query.moviehash = currentMoviehash
        do {
            let results = try await subtitles.search(query, languages: ["en", "he"])
            guard let best = rankedBest(results) else {
                note("film end: no subtitle to time it by")
                return
            }
            let url = try await subtitles.download(best)
            guard !Task.isCancelled, !isTornDown, contentEndTime == nil,
                  let (text, _) = Self.readSubtitleText(at: url),
                  let lastCue = SubtitleTiming.lastCueEndSeconds(in: text) else { return }
            // Retimed exactly as `prepareSubtitle` would, had the viewer attached it: a subtitle
            // authored at 25fps ends ~4% early on a 23.976 file.
            let factor = SubtitleRetimer.factor(subtitleFPS: best.fps, videoFPS: engine.videoFPS,
                                                lastCueEnd: lastCue, duration: length)
            contentEndTime = lastCue * (factor ?? 1)
            note("film end: last line at \(Timecode.format(contentEndTime ?? 0))")
        } catch {
            // Out of quota, no account, offline: the estimate stands, and the viewer is not told —
            // nothing they asked for failed.
            note("film end: subtitle lookup failed: \(error)")
        }
    }
}
