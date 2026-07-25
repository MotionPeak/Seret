import Foundation
import DebridCore

extension PlayerModel {

    // MARK: - Up Next (binge)

    /// Reveal the "Up Next" bar once playback passes the content-end threshold (last subtitle cue,
    /// or a tail fallback) for a show with another episode — unless the viewer dismissed it.
    func maybeShowUpNext() {
        guard hasNextEpisode, !upNextDismissed, !upNextVisible, phase == .playing,
              duration > 0, let threshold = upNextThreshold,
              position >= threshold, position < duration else { return }
        upNextVisible = true
        // Warm the next episode's unrestrict now (fire-and-forget) — by the time the countdown
        // auto-advances (or Play Now is tapped), the playable URL is already resolved.
        if let next = nextEpisode { prefetchLink?(next.source.restrictedLink) }
        upNextSecondsRemaining = upNextCountdownStart
        upNextTask?.cancel()
        upNextTask = Task { @MainActor in
            while upNextSecondsRemaining > 0 {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                upNextSecondsRemaining -= 1
            }
            playNext()                      // countdown elapsed → advance
        }
    }

    /// Dismiss the Up Next bar and stop it from re-appearing for this episode (the viewer wants to
    /// watch the credits). The file's real end then exits rather than auto-advancing.
    public func dismissUpNext() {
        upNextTask?.cancel()
        upNextVisible = false
        upNextDismissed = true
    }

    /// "Play Now" on the Up Next bar — advance immediately, skipping the countdown.
    public func playNextNow() {
        upNextTask?.cancel()
        playNext()
    }

    func resetUpNext() {
        upNextTask?.cancel()
        upNextVisible = false
        upNextDismissed = false
        upNextSecondsRemaining = 0
        contentEndTime = nil
    }

    /// Swap the playing episode to the next in series order and reload from the start, in-place (no
    /// teardown/re-present, same engine + event loop). Subtitle state resets — externals are
    /// per-episode. Caller is responsible for recording the outgoing episode's progress.
    func advanceToNextEpisode() {
        guard let next = nextEpisode else { return }
        switchTo(next, resumeAt: nil)
    }

    /// Swap the playing episode in-place (no teardown/re-present, same engine + event loop) and
    /// reload. Subtitle/track selection resets — externals are per-episode. Caller records the
    /// outgoing episode's progress.
    func switchTo(_ ep: Episode, resumeAt newResume: Double?) {
        resetUpNext()                        // clear the bar/countdown + the old episode's content-end
        isSwitching = true                   // swallow the old media's late `.ended` until E2 renders
        episode = ep
        sources = [ep.source]
        sourceIndex = 0
        contentKey = WatchKey.content(forShow: item, episode: ep)
        label = "\(item.title) — S\(ep.season)·E\(ep.number)"
        resumeAt = newResume
        fromStart = false                    // the new episode resumes via the provider if mid-watched
        selectedAudioID = nil
        selectedSubtitleID = nil
        pendingSubtitleAttach = nil
        let initial: SubtitleRowState = subtitles == nil ? .noAccount : .idle
        subtitleRows = ["he", "en"].map { SubtitleRow(language: $0, state: initial) }
        reload()
    }

    /// Switch playback to a chosen episode of the season, in-place (records the current episode's
    /// progress first). No-op if it's already the one playing. Resumes from the episode's saved
    /// position when partially watched (the resume provider decides); otherwise from the start.
    public func play(_ ep: Episode) {
        guard ep.season != episode?.season || ep.number != episode?.number else { return }
        Task { await self.recordCurrentProgress() }
        switchTo(ep, resumeAt: nil)
    }

    /// Build the strip: the WHOLE current season from TMDB (so every episode shows, not just the
    /// downloaded ones), each tagged with its owned/playable episode when in the library. Falls
    /// back to owned-only if TMDB is unavailable. Shows only; no-op once loaded for this season.
    public func loadSeasonEpisodes() async {
        guard let episode else { return }
        if let first = seasonEpisodes.first, first.season == episode.season { return }
        let owned = item.seasons.first(where: { $0.number == episode.season })?.episodes ?? []
        let ownedByNumber = Dictionary(owned.map { ($0.number, $0) }, uniquingKeysWith: { a, _ in a })

        if let details, let tmdbID = item.tmdbID,
           let eps = try? await details.seasonEpisodes(tvID: tmdbID, season: episode.season), !eps.isEmpty {
            seasonEpisodes = eps.sorted { $0.episodeNumber < $1.episodeNumber }.map { e in
                PlayerEpisode(season: episode.season, number: e.episodeNumber,
                              name: e.name, stillPath: e.stillPath, owned: ownedByNumber[e.episodeNumber])
            }
        } else {
            // No TMDB → show the downloaded episodes only.
            seasonEpisodes = owned.sorted { $0.number < $1.number }.map {
                PlayerEpisode(season: $0.season, number: $0.number, name: nil, stillPath: nil, owned: $0)
            }
        }
    }

    /// Called at every playback end-point: teardown, finish, and episode switches. With a scrobble
    /// backend wired this is the `stop` event (Trakt finalizes the resume point / marks watched off
    /// it); otherwise it falls back to the original progress write.
    func recordCurrentProgress() async {
        if let onScrobbleStop {
            await onScrobbleStop(currentFraction)
        } else {
            await recordProgress(contentKey, WatchKey.source(currentSource), position, duration)
        }
    }
}
