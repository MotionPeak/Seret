import Foundation
import DebridCore

extension PlayerModel {

    // MARK: - Subtitles

    /// Download and attach a subtitle in `language`. Tapping a language pill is a manual choice,
    /// and has to be recorded as one — otherwise the automatic preference re-decides the moment the
    /// download attaches and `.tracksChanged` fires, and picks whatever muxed track happens to
    /// share the language. The viewer tapped the pill precisely because that muxed track was not
    /// what they wanted, and a slave's own language is often nil, so the muxed one won outright.
    public func requestSubtitle(language: String) async {
        let wasPicked = subtitlePickedByUser
        subtitlePickedByUser = true
        await downloadSubtitle(language: language)
        // A download that did not produce a track chose nothing. Leaving the flag latched disabled
        // the automatic preference for the rest of the session over a request that failed — so a
        // muxed track in the viewer's preferred language was never selected either.
        if pendingSubtitleAttach == nil, selectedSubtitleID == nil, !wasPicked {
            subtitlePickedByUser = false
        }
    }

    /// The automatic one-shot fallback: the same download, but not a viewer decision, so it does
    /// not lock out the automatic path. It only ever runs when the media has no track in that
    /// language, so there is nothing for the automatic path to override it with.
    func downloadSubtitleAutomatically(language: String) async {
        await downloadSubtitle(language: language)
    }

    private func downloadSubtitle(language: String) async {
        guard let subtitles else { setRow(language, .noAccount); return }
        guard subtitleRows.first(where: { $0.language == language })?.state != .downloading else { return }
        setRow(language, .downloading)
        do {
            // A show must search by season + episode. This was `SubtitleQuery.movie(item)`
            // unconditionally, so every episode searched as if it were a film — the episode
            // builder existed and had never been called.
            var query = episode.map { SubtitleQuery.episode(show: item, episode: $0) }
                ?? SubtitleQuery.movie(item)
            // Match the file actually playing, exactly as the browser does. This took
            // `results.first` — whatever OpenSubtitles happened to return first — so the one-tap
            // pill regularly attached a subtitle timed against a DIFFERENT release. That drifts
            // linearly: right at the start, then each cue lands progressively early until it is
            // clipped by its successor and no sentence finishes on screen.
            await resolveMoviehashIfNeeded()
            query.moviehash = currentMoviehash
            let results = try await subtitles.search(query, languages: [language])
            guard let best = rankedBest(results) else { setRow(language, .error); return }
            let url = try await subtitles.download(best)
            // Requesting a language IS choosing it — make it sticky so the next episode/title
            // auto-downloads the same language without re-picking.
            trackPreferences?.record(subtitle: .language(language), forTitle: item.id)
            // Correct the timing when this subtitle was authored against a different frame rate.
            let attachURL = prepareSubtitle(at: url, declaredFPS: best.fps)
            // VLCKit attaches the slave asynchronously and signals via `.tracksChanged`; the new
            // track is usually NOT in the list yet. Remember the pending attach and finish it in
            // `refreshTracks()` once the track appears — that auto-selects it and turns the engine's
            // generic "Track N" into the language pill. Try once now in case it landed synchronously.
            let before = Set(engine.subtitleTracks.map(\.id))
            engine.addExternalSubtitle(url: attachURL)
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
                                                       videoFPS: engine.videoFPS)
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
            let attachURL = prepareSubtitle(at: url, declaredFPS: ranked.result.fps)
            let before = Set(engine.subtitleTracks.map(\.id))
            engine.addExternalSubtitle(url: attachURL)
            pendingSubtitleAttach = (ranked.result.language, before)
            refreshTracks()
            scheduleSubtitleAttachTimeout(language: ranked.result.language)
        } catch {
            subtitleSearchState = .failed
        }
    }

    /// The best-matching result for the file playing, or nil when there are none.
    ///
    /// One definition, because both subtitle paths need it and they used to disagree: the browser
    /// ranked, the one-tap pill took `results.first`. Ranking scores a moviehash match (+1000), a
    /// shared release group, matching resolution/source, and the fps agreement that decides
    /// whether a subtitle will drift.
    func rankedBest(_ results: [SubtitleResult]) -> SubtitleResult? {
        SubtitleMatch.rank(results, against: currentSource.releaseNameForMatching,
                           videoFPS: engine.videoFPS).first?.result
    }

    /// Prepare a freshly-downloaded subtitle for attachment: correct its timing when it was
    /// authored against a different frame rate, and note where its dialogue ends.
    ///
    /// Returns the URL to hand the engine — the corrected copy when a correction applied, the file
    /// as downloaded otherwise. The correction is written to a SEPARATE file on purpose: downloads
    /// are cached on disk by `file_id`, so rewriting one in place would correct an
    /// already-corrected file again on the next play, and would corrupt it outright for a different
    /// release of the same episode that legitimately shares the subtitle.
    func prepareSubtitle(at url: URL, declaredFPS: Double?) -> URL {
        // Timestamps are ASCII, so isoLatin1 is a safe fallback decode for non-UTF-8 (e.g.
        // windows-1255 Hebrew) files — and it is byte-preserving, so writing back in the encoding
        // it was read in reproduces the original bytes everywhere except the cue lines we mean to
        // rewrite. Decoding Hebrew as UTF-8 would fail outright, which is why this order matters.
        var decoded: String?
        var encoding = String.Encoding.utf8
        if let text = try? String(contentsOf: url, encoding: .utf8) {
            decoded = text
        } else if let text = try? String(contentsOf: url, encoding: .isoLatin1) {
            decoded = text
            encoding = .isoLatin1
        }
        guard let text = decoded else { return url }

        // The cues tell us when the dialogue ends → drives "Up Next" at content-end rather than at
        // the file end, which on a TV rip is minutes of credits later.
        let lastCue = SubtitleTiming.lastCueEndSeconds(in: text)
        contentEndTime = lastCue
        subtitleRetimeFactor = nil

        guard let factor = SubtitleRetimer.factor(subtitleFPS: declaredFPS,
                                                  videoFPS: engine.videoFPS,
                                                  lastCueEnd: lastCue,
                                                  duration: duration > 0 ? duration : nil)
        else { return url }

        let corrected = SubtitleRetimer.rescale(text, by: factor)
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("retimed-\(url.lastPathComponent)")
        guard (try? corrected.write(to: destination, atomically: true, encoding: encoding)) != nil
        else { return url }        // a failed write must not cost the viewer the subtitle entirely
        // Every cue moved, including the last one Up Next keys off.
        contentEndTime = SubtitleTiming.lastCueEndSeconds(in: corrected) ?? lastCue
        subtitleRetimeFactor = factor
        return destination
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
        guard let pending = pendingSubtitleAttach else { return }
        // Any track that was not there when the download started is a candidate — but VLCKit parses
        // a media's own tracks progressively, so a MUXED one can surface in that same window and be
        // mistaken for the slave. Prefer an external track, which is unambiguously the file we just
        // attached; fall back to the first newcomer when the engine reports none as external.
        let newcomers = engine.subtitleTracks.filter { !pending.before.contains($0.id) }
        guard let newID = (newcomers.first(where: \.isExternal) ?? newcomers.first)?.id
        else { return }
        #if DEBUG
        subtitleProbe("SELECT \(newID) (attach of downloaded \(pending.language)) <- FLUSHES SPU")
        #endif
        engine.selectSubtitleTrack(id: newID)
        selectedSubtitleID = newID
        setRow(pending.language, .attached(newID))
        pendingSubtitleAttach = nil
        subtitleAttachTimeoutTask?.cancel()      // it landed — nothing left to time out
        subtitleAttachTimeoutTask = nil
    }

    /// Fallback if VLCKit never attaches the slave (e.g. an unreadable file): clear the pending
    /// download after a grace period so its row stops spinning and shows the retry-able error.
    ///
    /// Held and cancelled, because it re-checks only the LANGUAGE. Left running it outlived the
    /// episode that armed it: E1's timer would wake eight seconds later, match E2's freshly-pending
    /// Hebrew download by name, clear it and mark the row `.error` — so E2 got no subtitles at all
    /// and an error badge on a download that had in fact succeeded.
    func scheduleSubtitleAttachTimeout(language: String) {
        subtitleAttachTimeoutTask?.cancel()
        subtitleAttachTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled, let self else { return }
            self.failPendingSubtitleAttach(language: language)
        }
    }

    /// Test seam: run the give-up path now instead of waiting out the timeout.
    func failPendingSubtitleAttachForTesting() {
        subtitleAttachTimeoutTask?.cancel()
        guard let language = pendingSubtitleAttach?.language else { return }
        failPendingSubtitleAttach(language: language)
    }

    /// The attach never landed: the row failed, and whatever the request latched is released.
    private func failPendingSubtitleAttach(language: String) {
        guard pendingSubtitleAttach?.language == language else { return }
        pendingSubtitleAttach = nil
        setRow(language, .error)
        // The download chose nothing after all. Leaving the manual-pick latch set disabled the
        // automatic preference for the rest of the source, so a muxed track in the viewer's
        // language — one that may only have finished parsing while the download was being waited
        // on — was never selected either, and they got no subtitles at all.
        guard selectedSubtitleID == nil else { return }
        subtitlePickedByUser = false
        // Re-decide now: that track's `.tracksChanged` has already been and gone.
        subtitleSelectionSignature = []
        applyTrackPreferencesIfNeeded()
    }

    func setRow(_ language: String, _ state: SubtitleRowState) {
        guard let i = subtitleRows.firstIndex(where: { $0.language == language }) else { return }
        subtitleRows[i].state = state
    }
}
