import Foundation
import DebridCore

extension PlayerModel {

    // MARK: - Subtitles

    public func requestSubtitle(language: String) async {
        guard let subtitles else { setRow(language, .noAccount); return }
        guard subtitleRows.first(where: { $0.language == language })?.state != .downloading else { return }
        setRow(language, .downloading)
        do {
            // A show must search by season + episode. This was `SubtitleQuery.movie(item)`
            // unconditionally, so every episode searched as if it were a film — the episode
            // builder existed and had never been called.
            let query = episode.map { SubtitleQuery.episode(show: item, episode: $0) }
                ?? SubtitleQuery.movie(item)
            let results = try await subtitles.search(query, languages: [language])
            guard let best = results.first else { setRow(language, .error); return }
            let url = try await subtitles.download(best)
            // Requesting a language IS choosing it — make it sticky so the next episode/title
            // auto-downloads the same language without re-picking.
            trackPreferences?.record(subtitle: .language(language), forTitle: item.id)
            // The downloaded cues tell us when the dialogue ends → drives "Up Next" at content-end
            // rather than the file end. Timestamps are ASCII, so isoLatin1 is a safe fallback decode
            // for non-UTF-8 (e.g. windows-1255 Hebrew) files.
            if let text = (try? String(contentsOf: url, encoding: .utf8))
                ?? (try? String(contentsOf: url, encoding: .isoLatin1)) {
                contentEndTime = SubtitleTiming.lastCueEndSeconds(in: text)
            }
            // VLCKit attaches the slave asynchronously and signals via `.tracksChanged`; the new
            // track is usually NOT in the list yet. Remember the pending attach and finish it in
            // `refreshTracks()` once the track appears — that auto-selects it and turns the engine's
            // generic "Track N" into the language pill. Try once now in case it landed synchronously.
            let before = Set(engine.subtitleTracks.map(\.id))
            engine.addExternalSubtitle(url: url)
            pendingSubtitleAttach = (language, before)
            refreshTracks()
            scheduleSubtitleAttachTimeout(language: language)
        } catch let SubtitleError.dailyCapReached(reset) {
            setRow(language, .capReached(reset))
        } catch SubtitleError.notAuthenticated {
            setRow(language, .noAccount)
        } catch {
            setRow(language, .error)
        }
    }

    /// Search every subtitle for a language and rank them against the file actually playing. The
    /// moviehash is resolved once per source — two small range requests — turning a filename
    /// heuristic into a perfect-sync guarantee.
    public func searchSubtitles(language: String) async {
        guard let subtitles else { subtitleSearchState = .failed; return }
        subtitleSearchLanguage = language
        subtitleSearchState = .searching
        subtitleSearchResults = []
        await resolveMoviehashIfNeeded()
        var query = episode.map { SubtitleQuery.episode(show: item, episode: $0) }
            ?? SubtitleQuery.movie(item)
        query.moviehash = currentMoviehash
        do {
            let results = try await subtitles.search(query, languages: [language])
            subtitleSearchResults = SubtitleMatch.rank(results,
                                                       against: currentSource.releaseNameForMatching,
                                                       videoFPS: nil)
            subtitleSearchState = .loaded
        } catch {
            subtitleSearchState = .failed
        }
    }

    /// Download a chosen search result and attach it, reusing the same pending-attach handshake as
    /// the language rows (VLCKit surfaces a slave asynchronously via `.tracksChanged`).
    public func useSubtitle(_ ranked: SubtitleMatch.Ranked) async {
        guard let subtitles else { return }
        do {
            let url = try await subtitles.download(ranked.result)
            if let text = (try? String(contentsOf: url, encoding: .utf8))
                ?? (try? String(contentsOf: url, encoding: .isoLatin1)) {
                contentEndTime = SubtitleTiming.lastCueEndSeconds(in: text)
            }
            let before = Set(engine.subtitleTracks.map(\.id))
            engine.addExternalSubtitle(url: url)
            pendingSubtitleAttach = (ranked.result.language, before)
            refreshTracks()
            scheduleSubtitleAttachTimeout(language: ranked.result.language)
        } catch {
            subtitleSearchState = .failed
        }
    }

    func resolveMoviehashIfNeeded() async {
        guard !moviehashResolved else { return }
        moviehashResolved = true
        guard let url = try? await unrestrict(currentSource.restrictedLink) else { return }
        currentMoviehash = await MovieHash.remote(url: url)
    }

    /// If a downloaded subtitle's slave track has appeared in the engine, select it, mark its
    /// language row `.attached`, and clear the pending attach. Idempotent — safe to call on every
    /// `.tracksChanged`. Marking the row attached also drops the engine's generic "Track N" pill:
    /// `embeddedSubtitleTracks` excludes any id a language row now owns.
    func attachPendingSubtitleIfReady() {
        guard let pending = pendingSubtitleAttach,
              let newID = engine.subtitleTracks.first(where: { !pending.before.contains($0.id) })?.id
        else { return }
        engine.selectSubtitleTrack(id: newID)
        selectedSubtitleID = newID
        setRow(pending.language, .attached(newID))
        pendingSubtitleAttach = nil
    }

    /// Fallback if VLCKit never attaches the slave (e.g. an unreadable file): clear the pending
    /// download after a grace period so its row stops spinning and shows the retry-able error.
    func scheduleSubtitleAttachTimeout(language: String) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard let self, self.pendingSubtitleAttach?.language == language else { return }
            self.pendingSubtitleAttach = nil
            self.setRow(language, .error)
        }
    }

    func setRow(_ language: String, _ state: SubtitleRowState) {
        guard let i = subtitleRows.firstIndex(where: { $0.language == language }) else { return }
        subtitleRows[i].state = state
    }
}
