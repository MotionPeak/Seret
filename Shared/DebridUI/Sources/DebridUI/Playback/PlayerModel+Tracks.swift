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
        applySubtitlePreferenceOnce(prefs)
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

        switch prefs.preferredAudio {
        case .language(let lang):
            // Ranked, not first-match: the preference stores a LANGUAGE, so on a release that
            // carries both a lossless and a compatibility track in that language, first-match
            // would keep re-picking the one that doesn't play.
            if let match = audioTracks.bestAudio(forLanguage: lang) { applyAudioSelection(match) }
        case .automatic:
            // Default: English audio when the release has it; otherwise leave VLCKit's default,
            // which is the file's first/original-language track — so a foreign film or show plays
            // in its original language instead of a wrong dub.
            if let english = audioTracks.bestAudio(forLanguage: "en") {
                applyAudioSelection(english)
            } else if let first = audioTracks.first, let original = first.language,
                      let best = audioTracks.bestAudio(forLanguage: original), best.id != first.id {
                // No English: stay in the original language, but take the version of it that
                // actually decodes. Only when that DIFFERS from the file's first track, so a
                // release whose default is already the best keeps VLCKit's own choice untouched.
                applyAudioSelection(best)
            }
        case .off:
            break   // "off" isn't meaningful for audio — keep the default track
        }
    }

    /// Apply the subtitle preference once per source (`reload()` re-arms it). Unlike audio this
    /// must NOT repeat: the `.language` branch can kick off an on-demand download, and re-running
    /// it on every `.tracksChanged` would re-hit a daily-capped account every episode of a binge.
    func applySubtitlePreferenceOnce(_ prefs: TrackPreferenceStoring) {
        guard !trackPrefsApplied, !audioTracks.isEmpty else { return }
        trackPrefsApplied = true

        switch prefs.preferredSubtitle {
        case .automatic:
            break
        case .off:
            engine.selectSubtitleTrack(id: nil)
            selectedSubtitleID = nil
        case .language(let lang):
            if let match = subtitleTracks.first(where: { $0.language == lang }) {
                engine.selectSubtitleTrack(id: match.id)
                selectedSubtitleID = match.id
            } else if ["he", "en"].contains(lang),
                      subtitleRows.first(where: { $0.language == lang })?.state == .idle {
                Task { await self.requestSubtitle(language: lang) }
            }
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
        selectedSubtitleID = id
        engine.selectSubtitleTrack(id: id)
        recordPreferredSubtitle(forTrackID: id)
    }
    public func selectSubtitleOff() {
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
