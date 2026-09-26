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
        guard let subtitles else {
            // The state five plays on the Apple TV were in, and nothing in the log said so.
            note("\(language): NO PROVIDER — no OpenSubtitles account on this device")
            setRow(language, .noAccount)
            return
        }
        guard subtitleRows.first(where: { $0.language == language })?.state != .downloading else { return }
        // Already fetched this language and the track is still there? Then the ask is "put Hebrew
        // back on", not "fetch Hebrew again" — and re-fetching could not have answered it anyway,
        // because libvlc will not attach the same file twice. Spends no quota and no waiting.
        if let existing = downloadedTrack(forLanguage: language) {
            selectAttachedSubtitle(id: existing.id, language: language)
            return
        }
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
            note("\(language): search → \(results.count) results")
            guard let best = rankedBest(results) else {
                note("\(language): nothing matched this file")
                setRow(language, .error)
                return
            }
            let url = try await subtitles.download(best)
            // Requesting a language IS choosing it — make it sticky so the next episode/title
            // auto-downloads the same language without re-picking.
            trackPreferences?.record(subtitle: .language(language), forTitle: item.id)
            // Correct the timing when this subtitle was authored against a different frame rate.
            attach(prepareSubtitle(at: url, declaredFPS: best.fps), language: language)
        } catch let SubtitleError.dailyCapReached(reset) {
            note("\(language) FAILED: daily cap reached (resets \(reset?.description ?? "unknown"))")
            setRow(language, .capReached(reset))
        } catch SubtitleError.notAuthenticated {
            note("\(language) FAILED: OpenSubtitles refused the login")
            setRow(language, .noAccount)
        } catch {
            note("\(language) FAILED: \(error)")
            setRow(language, .error)
        }
    }

    /// Search every subtitle for a language and rank them against the file actually playing. The
    /// moviehash is resolved once per source — two small range requests — turning a filename
    /// heuristic into a perfect-sync guarantee.
    public func searchSubtitles(language: String) async {
        // Starting a search is the viewer moving on from whatever went wrong last time.
        subtitlePickFailure = nil
        guard let subtitles else {
            note("search \(language): NO PROVIDER — no OpenSubtitles account on this device")
            subtitlePickFailure = .noAccount
            subtitleSearchState = .failed
            return
        }
        subtitleSearchLanguage = language
        subtitleSearchState = .searching
        subtitleSearchResults = []
        await resolveMoviehashIfNeeded()
        var query = episode.map { SubtitleQuery.episode(show: item, episode: $0) }
            ?? SubtitleQuery.movie(item)
        query.moviehash = currentMoviehash
        do {
            let results = try await subtitles.search(query, languages: [language])
            note("search \(language) → \(results.count) results")
            subtitleSearchResults = SubtitleMatch.rank(results,
                                                       against: currentSource.releaseNameForMatching,
                                                       videoFPS: engine.videoFPS)
            subtitleSearchState = .loaded
        } catch {
            note("search \(language) FAILED: \(error)")
            subtitlePickFailure = Self.pickFailure(for: error)
            subtitleSearchState = .failed
        }
    }

    /// Download a chosen search result and attach it, reusing the same pending-attach handshake as
    /// the language rows (VLCKit surfaces a slave asynchronously via `.tracksChanged`).
    ///
    /// Picking a particular release out of the browser is a viewer decision exactly as much as
    /// tapping the language pill is, and it has to SAY so. It did not — so the automatic pick was
    /// still live, and the moment the slave appeared it re-decided over it and put the file's own
    /// track back. The viewer had gone to the trouble of choosing a specific subtitle and watched
    /// nothing change.
    /// - Returns: whether a subtitle was actually handed to the engine. The browser closes only on
    ///   `true`; on `false` it stays open and prints `subtitlePickFailure`, because a list that
    ///   vanishes having changed nothing is the whole complaint.
    @discardableResult
    public func useSubtitle(_ ranked: SubtitleMatch.Ranked) async -> Bool {
        // No provider at all — no OpenSubtitles account in this device's Keychain. This returned on
        // its own `guard` without a word, which on the Apple TV is a press that does nothing at all.
        guard let subtitles else { return failPick(.noAccount) }
        let wasPicked = subtitlePickedByUser
        subtitlePickedByUser = true
        do {
            let url = try await subtitles.download(ranked.result)
            note("subtitle pick: downloaded \(ranked.result.fileID) (\(ranked.result.language))")
            attach(prepareSubtitle(at: url, declaredFPS: ranked.result.fps),
                   language: ranked.result.language)
            subtitlePickFailure = nil
            return true
        } catch {
            // A pick that chose nothing must not leave the automatic path latched off for the rest
            // of the source — that would cost the viewer subtitles altogether over a failed fetch.
            if !wasPicked { subtitlePickedByUser = false }
            // Deliberately NOT `subtitleSearchState = .failed`: that describes the SEARCH, and the
            // browser draws its list from it. Marking it failed emptied the list the viewer was
            // standing in, so keeping the browser open bought them a reason and no way to act on
            // it. The search succeeded; one download did not.
            return failPick(Self.pickFailure(for: error))
        }
    }

    /// Record why a pick produced nothing, and leave the same line in the diagnostics log the next
    /// device report will be read from.
    @discardableResult
    private func failPick(_ reason: SubtitlePickFailure) -> Bool {
        subtitlePickFailure = reason
        note("subtitle pick FAILED: \(reason)")
        return false
    }

    static func pickFailure(for error: Error) -> SubtitlePickFailure {
        switch error {
        case SubtitleError.notAuthenticated:            .noAccount
        case SubtitleError.dailyCapReached(let reset):  .capReached(reset)
        default:                                        .failed
        }
    }

    /// Hand a downloaded subtitle file to the engine and wait for its track to appear.
    ///
    /// The wait is the whole reason this is a handshake: VLCKit surfaces a slave asynchronously via
    /// `.tracksChanged`, so the track is usually not in the list yet when `addExternalSubtitle`
    /// returns. `refreshTracks()` is called once here in case it landed synchronously.
    ///
    /// A file already attached this session is RE-SELECTED rather than re-attached, because libvlc
    /// keys a slave by URL and silently ignores a duplicate: no new track appears, so a handshake
    /// started for it would wait for something that can never arrive.
    func attach(_ url: URL, language: String) {
        if let id = attachedSubtitleTracks[url], engine.subtitleTracks.contains(where: { $0.id == id }) {
            selectAttachedSubtitle(id: id, language: language)
            return
        }
        let before = Set(engine.subtitleTracks.map(\.id))
        engine.addExternalSubtitle(url: url)
        pendingSubtitleAttach = (language, url, before)
        refreshTracks()
        scheduleSubtitleAttachTimeout(language: language)
    }

    /// Put an already-attached downloaded track back on screen and re-own it from its language row.
    func selectAttachedSubtitle(id: String, language: String) {
        note("\(language): re-selecting the track already attached for it")
        #if DEBUG
        subtitleProbe("SELECT \(id) (re-select of attached \(language)) <- FLUSHES SPU")
        #endif
        engine.selectSubtitleTrack(id: id)
        selectedSubtitleID = id
        setRow(language, .attached(id))
        subtitleTracks = engine.subtitleTracks
        reconcileSubtitleShift()     // the copy re-selected may not carry the offset now dialled
    }

    /// The track a subtitle downloaded for `language` is attached to, while it is still present.
    ///
    /// Asked of the ENGINE rather than the published mirror, as the rest of the attach path is: a
    /// language row's `.attached` id is positional, so it only means anything against the track
    /// list that exists right now, and a mirror a beat out of date would answer "gone" for a track
    /// that is there — sending the caller off to re-download a file libvlc will refuse to re-attach.
    func downloadedTrack(forLanguage language: String) -> MediaTrack? {
        guard let row = subtitleRows.first(where: { $0.language == language }),
              let id = attachedTrackID(row) else { return nil }
        return engine.subtitleTracks.first { $0.id == id }
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
        guard let (text, encoding) = Self.readSubtitleText(at: url) else { return url }

        // The cues tell us when the dialogue ends → drives "Up Next" at content-end rather than at
        // the file end, which on a TV rip is minutes of credits later.
        let lastCue = SubtitleTiming.lastCueEndSeconds(in: text)
        contentEndTime = lastCue
        subtitleRetimeFactor = nil
        // The same text, read once for two questions: when the dialogue ends, and what the lines
        // are. Keyed by the file that is about to be attached, which is what the panel looks up.
        subtitleCues[url] = SubtitleCues.parse(text)

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
        // The corrected copy is the file the engine gets, so it is the one whose cue times the
        // panel must show — every cue moved.
        subtitleCues[destination] = SubtitleCues.parse(corrected)
        return destination
    }

    /// A subtitle file's text, and the encoding to write a rewritten copy back in.
    ///
    /// Timestamps are ASCII, so isoLatin1 is a safe fallback decode for non-UTF-8 (e.g.
    /// windows-1255 Hebrew) files — and it is byte-preserving, so writing back in the encoding it
    /// was read in reproduces the original bytes everywhere except the cue lines we mean to
    /// rewrite. Decoding Hebrew as UTF-8 would fail outright, which is why this order matters.
    static func readSubtitleText(at url: URL) -> (String, String.Encoding)? {
        if let text = try? String(contentsOf: url, encoding: .utf8) { return (text, .utf8) }
        if let text = try? String(contentsOf: url, encoding: .isoLatin1) { return (text, .isoLatin1) }
        return nil
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
        attachedSubtitleTracks[pending.url] = newID   // libvlc will not attach this file again
        pendingSubtitleAttach = nil
        subtitleAttachTimeoutTask?.cancel()      // it landed — nothing left to time out
        subtitleAttachTimeoutTask = nil
        restoreSubtitleDelay()      // this file + this subtitle may already have been dialled in
        reconcileSubtitleShift()    // …and whatever is dialled now must be in the file on screen
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
        note("attach of \(language) never landed — giving up")
        setRow(language, .error)
        // A browser pick has no language row to carry the bad news, so it needs saying here too:
        // the download worked and the track never appeared, which on screen is the same silence.
        subtitlePickFailure = .failed
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

    /// One app-side line into the engine's diagnostics log, beside libvlc's own.
    func note(_ line: String) { engine.note("[subs] \(line)") }

    func setRow(_ language: String, _ state: SubtitleRowState) {
        guard let i = subtitleRows.firstIndex(where: { $0.language == language }) else { return }
        subtitleRows[i].state = state
    }
}
