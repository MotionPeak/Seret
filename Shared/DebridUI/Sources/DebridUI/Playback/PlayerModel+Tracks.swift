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

    /// Auto-apply the user's persisted audio/subtitle language once this source's tracks have been
    /// discovered (audio is always present, so its arrival means parsing is far enough along). Runs
    /// once per source (`reload()` re-arms it), so a later manual change isn't reverted by a
    /// subsequent `.tracksChanged`. A preferred he/en subtitle that isn't embedded auto-downloads —
    /// but only when its row is still `.idle`, so a daily-cap or in-flight download isn't re-hit
    /// every episode of a binge.
    func applyTrackPreferencesIfNeeded() {
        guard let prefs = trackPreferences, !trackPrefsApplied, !audioTracks.isEmpty else { return }
        trackPrefsApplied = true

        switch prefs.preferredAudio {
        case .language(let lang):
            if let match = audioTracks.first(where: { $0.language == lang }) {
                engine.selectAudioTrack(id: match.id)
                selectedAudioID = match.id
            }
        case .automatic:
            // Default: English audio when the release has it; otherwise leave VLCKit's default,
            // which is the file's first/original-language track — so a foreign film or show plays
            // in its original language instead of a wrong dub.
            if let english = audioTracks.first(where: { Self.isEnglishLanguage($0.language) }) {
                engine.selectAudioTrack(id: english.id)
                selectedAudioID = english.id
            }
        case .off:
            break   // "off" isn't meaningful for audio — keep the default track
        }

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

    /// Whether a track's language tag denotes English. VLCKit reports whatever libvlc parsed from the
    /// container — 2-letter ("en"), 3-letter ("eng"), or descriptive ("English", "en-US") — so match
    /// them all. An untagged (`nil`) track is never treated as English.
    static func isEnglishLanguage(_ language: String?) -> Bool {
        guard let l = language?.lowercased() else { return false }
        return l == "en" || l.hasPrefix("en-") || l.hasPrefix("eng")
    }

    public func selectAudio(id: String) {
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
