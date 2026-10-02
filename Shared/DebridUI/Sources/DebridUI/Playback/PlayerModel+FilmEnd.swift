import Foundation
import DebridCore

extension PlayerModel {

    // MARK: - Where the film ends

    /// How far into a film the player asks where it ends. Late enough that a film abandoned in its
    /// first act costs nothing; early enough that the answer is in long before the end.
    static let filmEndLookupFraction = 0.5

    /// Halfway into a film, find out where it ends — once.
    ///
    /// The watched line (and with it the Letterboxd rating prompt) is only as good as what the
    /// player knows. Without this, a film watched with an embedded subtitle, or none, fell back to
    /// an estimate that asked for a rating while the last scene was still playing. Films only: the
    /// prompt is for films.
    func measureFilmEndIfDue() {
        guard !filmEndMeasured, !isTornDown, episode == nil, duration > 0,
              position >= Self.filmEndLookupFraction * duration else { return }
        filmEndMeasured = true
        let length = duration
        filmEndTask = Task { @MainActor [weak self] in await self?.measureFilmEnd(duration: length) }
    }

    /// Asked in order of how well each answer fits THIS file:
    /// 1. the file's own subtitle index and chapters — its own timeline, nothing to correct;
    /// 2. TheIntroDB's credits timestamp — free, but crowdsourced for some cut of the film;
    /// 3. only when the file has no subtitle to read, one downloaded for the time of its last line.
    ///    Never attached: the viewer sees no change.
    func measureFilmEnd(duration length: Double) async {
        let fileHadASubtitle = await measureFilmEndFromFile(duration: length)
        guard !Task.isCancelled, !isTornDown, !knowsWhereTheFilmEnds(duration: length) else { return }

        if let credits, let tmdbID = item.tmdbID {
            do {
                if let start = try await credits.creditsStart(tmdbID: tmdbID, durationSeconds: length) {
                    creditsStartTime = creditsStartTime.map { max($0, start) } ?? start
                }
                note("film end: database credits at \(creditsStartTime.map { Timecode.format($0) } ?? "unknown")")
            } catch {
                note("film end: credits lookup failed: \(error)")
            }
        }
        // A file whose own subtitle could not say — it runs on through the credits song — would get
        // no better answer from another release's subtitle; the estimate stands.
        guard !Task.isCancelled, !isTornDown, !fileHadASubtitle,
              !knowsWhereTheFilmEnds(duration: length), contentEndTime == nil,
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
            note("film end: downloaded subtitle's last line at \(Timecode.format(contentEndTime ?? 0))")
        } catch {
            // Out of quota, no account, offline: the estimate stands, and the viewer is not told —
            // nothing they asked for failed.
            note("film end: subtitle lookup failed: \(error)")
        }
    }

    /// Read the playing file's own subtitle index and chapters (`FilmEnding`). Returns whether the
    /// file had a full subtitle to read, whether or not it could say where the film ends.
    private func measureFilmEndFromFile(duration length: Double) async -> Bool {
        guard let readIndex, let url = try? await unrestrict(currentSource.restrictedLink),
              !Task.isCancelled, !isTornDown,
              let index = await readIndex(url), !Task.isCancelled, !isTornDown else { return false }
        let ending = FilmEnding.measure(index, duration: length)
        if let end = ending.dialogueEnd {
            contentEndTime = end
            filmEndFromFile = true
        }
        if let start = ending.creditsStart { creditsStartTime = start }
        note("film end: file says last line \(ending.dialogueEnd.map { Timecode.format($0) } ?? "unknown"), "
             + "credits chapter \(ending.creditsStart.map { Timecode.format($0) } ?? "none"), "
             + "track \(ending.usableTrack?.name ?? ending.usableTrack?.language ?? "none")")
        return ending.usableTrack != nil
    }

    /// Whether anything known is believable evidence of where THIS file's film ends.
    private func knowsWhereTheFilmEnds(duration length: Double) -> Bool {
        WatchThreshold.evidence(duration: length, lastSubtitleCue: contentEndTime,
                                creditsStart: creditsStartTime) != nil
    }
}
