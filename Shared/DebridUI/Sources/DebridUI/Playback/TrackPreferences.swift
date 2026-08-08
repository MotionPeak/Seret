import Foundation
import Observation

/// A persisted track preference. Stored by **language**, never by raw track id (`audio/0`/`spu/1`
/// aren't stable across episodes/files), so the choice carries to the next episode and the next title.
public enum TrackChoice: Equatable, Sendable {
    /// No preference recorded yet → let VLCKit pick its default.
    case automatic
    /// Explicitly off (subtitles only) — distinct from `.automatic` so an intentional "no subs"
    /// isn't re-defaulted to an embedded sub on the next play.
    case off
    /// Prefer the track whose language matches this code (e.g. "en", "he").
    case language(String)
}

/// Seam over the app-global preferred audio + subtitle languages. `PlayerModel` records the user's
/// pick here and auto-applies it when each playback's tracks load. The concrete `TrackPreferences`
/// is `UserDefaults`-backed; tests inject a fake.
@MainActor
public protocol TrackPreferenceStoring: AnyObject {
    /// The library-wide default, updated by every manual pick so a title never seen before still
    /// opens the way the viewer last chose.
    var preferredAudio: TrackChoice { get set }
    var preferredSubtitle: TrackChoice { get set }

    /// This title's own choice if it has one, otherwise the library-wide default.
    ///
    /// `titleID` is the MOVIE or SHOW id — never an episode's — so a series keeps one choice across
    /// all of its episodes instead of forgetting between them.
    func resolvedAudio(forTitle titleID: String) -> TrackChoice
    func resolvedSubtitle(forTitle titleID: String) -> TrackChoice
    /// Record a manual pick against this title AND as the new library-wide default.
    func record(audio: TrackChoice, forTitle titleID: String)
    func record(subtitle: TrackChoice, forTitle titleID: String)
}

/// Defaults so a store that only holds the global preference (a test fake) still satisfies the
/// protocol. These are requirements rather than extension-only methods on purpose: `PlayerModel`
/// holds the store as an existential, and an extension-only method would dispatch statically to
/// this default and silently ignore the real implementation.
public extension TrackPreferenceStoring {
    func resolvedAudio(forTitle titleID: String) -> TrackChoice { preferredAudio }
    func resolvedSubtitle(forTitle titleID: String) -> TrackChoice { preferredSubtitle }
    func record(audio: TrackChoice, forTitle titleID: String) { preferredAudio = audio }
    func record(subtitle: TrackChoice, forTitle titleID: String) { preferredSubtitle = subtitle }
}

/// Observable, `UserDefaults`-persisted track preferences. App-global (one preferred audio +
/// subtitle language for the whole library — the binge case: Hebrew subs every episode without
/// re-picking). Lives on `AppSession`; injected into every `PlayerModel`. Mirrors
/// `TrailerSettingsModel`.
@MainActor
@Observable
public final class TrackPreferences: TrackPreferenceStoring {
    public var preferredAudio: TrackChoice {
        didSet { Self.write(preferredAudio, to: defaults, key: Self.audioKey) }
    }
    public var preferredSubtitle: TrackChoice {
        didSet { Self.write(preferredSubtitle, to: defaults, key: Self.subtitleKey) }
    }

    private let defaults: UserDefaults
    private static let audioKey = "seret.preferredAudioTrack"
    private static let subtitleKey = "seret.preferredSubtitleTrack"
    private static let titleAudioKey = "seret.titleAudioTracks"
    private static let titleSubtitleKey = "seret.titleSubtitleTracks"

    // MARK: - Per-title overrides
    //
    // Device-local, like the global preference above. Values use the same encoding, and a title
    // with no entry inherits the global default — so choosing a language on one title still
    // carries to everything not explicitly set.

    public func resolvedAudio(forTitle titleID: String) -> TrackChoice {
        Self.decode(map(Self.titleAudioKey)[titleID]) ?? preferredAudio
    }

    public func resolvedSubtitle(forTitle titleID: String) -> TrackChoice {
        Self.decode(map(Self.titleSubtitleKey)[titleID]) ?? preferredSubtitle
    }

    public func record(audio: TrackChoice, forTitle titleID: String) {
        preferredAudio = audio                       // the next unseen title inherits this
        store(audio, forTitle: titleID, key: Self.titleAudioKey)
    }

    public func record(subtitle: TrackChoice, forTitle titleID: String) {
        preferredSubtitle = subtitle
        store(subtitle, forTitle: titleID, key: Self.titleSubtitleKey)
    }

    private func map(_ key: String) -> [String: String] {
        defaults.dictionary(forKey: key) as? [String: String] ?? [:]
    }

    private func store(_ choice: TrackChoice, forTitle titleID: String, key: String) {
        var m = map(key)
        switch choice {
        // `.automatic` is "no opinion", so it CLEARS the override rather than pinning one — that is
        // how a title returns to following the library-wide default.
        case .automatic:       m[titleID] = nil
        case .off:             m[titleID] = "off"
        case .language(let l): m[titleID] = l
        }
        defaults.set(m, forKey: key)
    }

    /// nil = this title has no override of its own.
    private static func decode(_ raw: String?) -> TrackChoice? {
        switch raw {
        case .none, .some(""): return nil
        case .some("off"):     return .off
        case .some(let l):     return .language(l)
        }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        preferredAudio = Self.read(defaults, key: Self.audioKey)
        preferredSubtitle = Self.read(defaults, key: Self.subtitleKey)
    }

    /// Encoding: "" = automatic, "off" = off, anything else = a language code. ("off" is not a real
    /// language code, so it can't collide.)
    private static func write(_ choice: TrackChoice, to defaults: UserDefaults, key: String) {
        switch choice {
        case .automatic:        defaults.removeObject(forKey: key)
        case .off:              defaults.set("off", forKey: key)
        case .language(let l):  defaults.set(l, forKey: key)
        }
    }

    private static func read(_ defaults: UserDefaults, key: String) -> TrackChoice {
        switch defaults.string(forKey: key) {
        case .none, "":  return .automatic
        case "off":      return .off
        case .some(let l): return .language(l)
        }
    }
}
