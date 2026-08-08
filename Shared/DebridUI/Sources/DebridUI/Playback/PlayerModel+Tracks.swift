import Foundation
import DebridCore

extension PlayerModel {

    // MARK: - Tracks

    /// Pull the engine's current track lists into the published state. Called when playback starts
    /// and on every `.tracksChanged` event (VLCKit discovers elementary streams asynchronously, and
    /// an on-demand external subtitle appears after load).
    func refreshTracks() {
        audioTracks = engine.audioTracks
        subtitleTracks = engine.subtitleTracks
        attachPendingSubtitleIfReady()
        applyTrackPreferencesIfNeeded()
        if volumePercent != 100 { engine.setVolume(volumePercent) }   // re-assert a boost post-swap
    }

    /// Auto-apply the user's persisted audio/subtitle language as this source's tracks are
    /// discovered. Audio and subtitles latch differently — see each method.
    func applyTrackPreferencesIfNeeded() {
        guard let prefs = trackPreferences else { return }
        applyAudioPreference(prefs)
        applySubtitlePreference(prefs)
    }

    /// The preferred audio language to hand the engine at LOAD time, so it opens the right track
    /// instead of being corrected afterwards (see `VideoPlayerEngine.load`).
    ///
    /// Both spellings are offered because containers tag either way — an MKV may say `eng` or `en`
    /// — and libvlc matches this string against whatever the container wrote. `.automatic` means
    /// English, matching the runtime rule below; `.off` leaves the engine's own choice alone.
    var preferredAudioLanguageOption: String? {
        switch trackPreferences?.preferredAudio {
        case .language(let lang): return Self.languageSpellings(lang)
        case .automatic:          return Self.languageSpellings("en")
        case .off, nil:           return nil
        }
    }

    /// "en" → "en,eng". Falls back to the tag alone for anything not in the app's own set.
    static func languageSpellings(_ tag: String) -> String {
        let stem = String(tag.lowercased().prefix(2))
        let threeLetter = ["en": "eng", "he": "heb"][stem]
        return threeLetter.map { "\(stem),\($0)" } ?? tag
    }

    /// Choose the audio track, re-deciding for as long as the track set keeps growing.
    ///
    /// It cannot latch on the first non-empty list the way the subtitle side does. VLCKit discovers
    /// elementary streams ONE AT A TIME, so a REMUX's first `.tracksChanged` typically carries only
    /// the lossless track and its AC-3 companion arrives a beat later. Deciding once would pin the
    /// choice to whichever track happened to be parsed first — exactly the undecodable one the
    /// ranking exists to avoid. So the pick is recomputed whenever the set of track ids changes,
    /// and stops for good the moment the viewer chooses by hand.
    func applyAudioPreference(_ prefs: TrackPreferenceStoring) {
        guard !audioPickedByUser, !audioTracks.isEmpty else { return }
        let signature = audioTracks.map(\.id)
        guard signature != audioSelectionSignature else { return }   // nothing new to reconsider
        audioSelectionSignature = signature

        let desired: MediaTrack?
        let language: String?
        switch prefs.preferredAudio {
        case .language(let lang):
            // Ranked, not first-match: the preference stores a LANGUAGE, so on a release that
            // carries both a lossless and a compatibility track in that language, first-match
            // would keep re-picking the one that doesn't play.
            desired = audioTracks.bestAudio(forLanguage: lang)
            language = lang
        case .automatic:
            // Default: English audio when the release has it; otherwise leave VLCKit's default,
            // which is the file's first/original-language track — so a foreign film or show plays
            // in its original language instead of a wrong dub.
            if let english = audioTracks.bestAudio(forLanguage: "en") {
                desired = english
                language = "en"
            } else if let first = audioTracks.first, let original = first.language,
                      let best = audioTracks.bestAudio(forLanguage: original), best.id != first.id {
                // No English: stay in the original language, but take the version of it that
                // actually decodes. Only when that DIFFERS from the file's first track, so a
                // release whose default is already the best keeps the engine's own choice untouched
                // even when the engine cannot tell us what it selected.
                desired = best
                language = original
            } else {
                desired = nil
                language = nil
            }
        case .off:
            desired = nil   // "off" isn't meaningful for audio — keep the default track
            language = nil
        }
        guard let desired, shouldOverrideEngineChoice(with: desired, preferring: language) else { return }
        applyAudioSelection(desired)
    }

    /// Whether moving to `desired` is worth what it costs.
    ///
    /// It is never free: selecting an audio track mid-playback makes libvlc kill the decoder and
    /// build a new one (`killing decoder` → `removing "audio decoder"` → `codec (ac3) started`),
    /// which is an audible drop-out. The log from a real REMUX showed us doing exactly that to
    /// swap between two tracks of the SAME codec — the engine had already picked a perfectly good
    /// AC-3 track and we "corrected" it to another AC-3 track, twice, before the film had started.
    ///
    /// So the bar is: only override the engine when the viewer actually gets something for it —
    /// the language they asked for, or a codec that will not fall over. Otherwise leave it be.
    func shouldOverrideEngineChoice(with desired: MediaTrack, preferring language: String?) -> Bool {
        // No engine has told us what it selected (older engine, or a test fake) — behave as before.
        guard let current = audioTracks.first(where: \.isSelected) else { return true }
        if current.id == desired.id { return false }
        if let language, !current.matchesLanguage(language) { return true }   // wrong language
        return desired.audioDecodeTier < current.audioDecodeTier              // else: only to escape a bad codec
    }

    /// Apply the subtitle preference, re-deciding for as long as the track set keeps growing.
    ///
    /// This used to run exactly once, gated on AUDIO tracks being present — and that is the bug
    /// behind "I have to turn the subtitles on again every time". VLCKit discovers elementary
    /// streams one at a time (the audio path above documents the same hazard), so at the moment the
    /// first audio track appeared the subtitle set was routinely still empty: no match was found,
    /// the latch closed, and the embedded track arriving a beat later was never looked at again.
    ///
    /// Selection is idempotent and free, so it simply re-runs whenever the subtitle set changes.
    /// The DOWNLOAD fallback is the part that must stay one-shot — it spends a daily-capped
    /// quota — so it is deferred to `arrangeSubtitleFallback` rather than fired the instant no
    /// match is found among tracks that may not all have arrived.
    func applySubtitlePreference(_ prefs: TrackPreferenceStoring) {
        guard !subtitlePickedByUser else { return }

        switch prefs.preferredSubtitle {
        case .automatic:
            return
        case .off:
            // Asserted immediately — "off" needs no discovery — and RE-asserted whenever the track
            // set changes, because a subtitle stream discovered later can be auto-enabled by the
            // engine (a forced/default track), which would put subtitles back on screen after the
            // viewer turned them off.
            let signature = subtitleTracks.map(\.id)
            guard !subtitleOffAsserted || signature != subtitleSelectionSignature else { return }
            subtitleSelectionSignature = signature
            subtitleOffAsserted = true
            engine.selectSubtitleTrack(id: nil)
            selectedSubtitleID = nil
        case .language(let lang):
            let signature = subtitleTracks.map(\.id)
            defer { arrangeSubtitleFallback(for: lang) }
            guard signature != subtitleSelectionSignature else { return }
            subtitleSelectionSignature = signature
            guard let match = subtitleTracks.first(where: { $0.language == lang }) else { return }
            subtitleFallbackTask?.cancel()          // an embedded track beat the download to it
            subtitleFallbackTask = nil
            subtitleFallbackRequested = true
            guard match.id != selectedSubtitleID else { return }
            engine.selectSubtitleTrack(id: match.id)
            selectedSubtitleID = match.id
        }
    }

    /// Arm the one-shot download fallback for a language with no embedded track.
    ///
    /// Deliberately delayed. There is no "track discovery finished" event, so firing the moment no
    /// match is found cannot tell "this release has no subtitles" from "they have not been parsed
    /// yet" — and getting that wrong spends a download from a daily-capped account on a file that
    /// already carries the track. Waiting `subtitleFallbackDelay` lets discovery settle; an
    /// embedded match arriving in the meantime cancels this.
    func arrangeSubtitleFallback(for language: String) {
        guard !subtitleFallbackRequested, subtitleFallbackTask == nil,
              ["he", "en"].contains(language),
              subtitleRows.first(where: { $0.language == language })?.state == .idle else { return }
        subtitleFallbackTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(subtitleFallbackDelay))
            guard !Task.isCancelled, !subtitlePickedByUser, !subtitleFallbackRequested,
                  !subtitleTracks.contains(where: { $0.language == language }) else { return }
            subtitleFallbackRequested = true
            await self.requestSubtitle(language: language)
        }
    }

    /// Select an audio track on the engine and mirror it into published state. Re-selecting the
    /// track that is already playing restarts VLCKit's audio output for nothing — an audible gap of
    /// exactly the kind this file exists to remove — so a no-op pick stays a no-op.
    private func applyAudioSelection(_ track: MediaTrack) {
        guard track.id != selectedAudioID else { return }
        engine.selectAudioTrack(id: track.id)
        selectedAudioID = track.id
    }

    public func selectAudio(id: String) {
        audioPickedByUser = true      // stop the automatic pick from re-deciding over them
        selectedAudioID = id
        engine.selectAudioTrack(id: id)
        if let lang = audioTracks.first(where: { $0.id == id })?.language {
            trackPreferences?.preferredAudio = .language(lang)
        }
    }

    public func selectSubtitle(id: String) {
        subtitlePickedByUser = true       // stop the automatic choice from re-deciding over them
        subtitleFallbackTask?.cancel()
        selectedSubtitleID = id
        engine.selectSubtitleTrack(id: id)
        recordPreferredSubtitle(forTrackID: id)
    }
    public func selectSubtitleOff() {
        subtitlePickedByUser = true
        subtitleFallbackTask?.cancel()
        selectedSubtitleID = nil
        engine.selectSubtitleTrack(id: nil)
        trackPreferences?.preferredSubtitle = .off
    }

    /// Persist a manually-selected subtitle by language. A downloaded sub's engine track often has a
    /// nil language, so resolve it from the owning language row first, then fall back to the track's
    /// own language tag (embedded subs).
    func recordPreferredSubtitle(forTrackID id: String) {
        if let row = subtitleRows.first(where: { attachedTrackID($0) == id }) {
            trackPreferences?.preferredSubtitle = .language(row.language)
        } else if let lang = subtitleTracks.first(where: { $0.id == id })?.language {
            trackPreferences?.preferredSubtitle = .language(lang)
        }
    }

    /// Set output volume (100 = unity, up to 200 = boost). Clamped; applied immediately and re-asserted
    /// by `refreshTracks()` so it sticks across track changes and episode swaps.
    public func setVolume(_ percent: Int) {
        volumePercent = min(200, max(0, percent))
        engine.setVolume(volumePercent)
    }
}
