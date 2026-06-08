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
    var preferredAudio: TrackChoice { get set }
    var preferredSubtitle: TrackChoice { get set }
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
