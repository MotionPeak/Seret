import Foundation

/// The lifecycle of a playback session, as the engine reports it.
public enum PlaybackState: Sendable, Equatable {
    case idle, buffering, playing, paused, ended
    case failed(String)
}

extension PlaybackState {
    /// Reconcile what the engine REPORTS against what the app actually ASKED FOR.
    ///
    /// Underlying players report transport states that the viewer never requested. libvlc is the
    /// case this exists for: stepping a single frame — which is how a seek is made visible while
    /// paused — announces `.playing` for the duration of the step. Taken at face value that reads
    /// as "the viewer resumed", and on tvOS the paused UI is torn down underneath them: the scrub
    /// bar hides and swipe-scrubbing disarms mid-gesture.
    ///
    /// So where the two disagree, intent wins. Only `.playing` is overridden — `.buffering`,
    /// `.ended` and `.failed` are things that genuinely happen to a paused player and must pass
    /// through untouched.
    public func reconciled(playbackRequested: Bool) -> PlaybackState {
        self == .playing && !playbackRequested ? .paused : self
    }
}

/// The current playhead position and total duration, in seconds.
public struct PlaybackTime: Sendable, Equatable {
    public var position: Double
    public var duration: Double
    public init(position: Double, duration: Double) {
        self.position = position
        self.duration = duration
    }
}

public enum TrackKind: Sendable, Equatable {
    case audio, subtitle
}

/// A selectable audio or subtitle track surfaced by the engine.
public struct MediaTrack: Sendable, Equatable, Identifiable {
    public let id: String
    public let kind: TrackKind
    public let name: String
    public let language: String?
    /// True for a track attached from a downloaded subtitle file rather than one muxed into the
    /// media. Lets the picker group "in this file" apart from "downloaded".
    public let isExternal: Bool
    /// The codec's four-character code as the container reports it — "a52 ", "trhd", "mp4a".
    /// nil when the engine can't tell. Drives `mostDecodableFirst()`: which audio codec is chosen
    /// decides whether a REMUX plays at all on tvOS, so it has to survive up to the picker.
    public let codec: String?
    /// Channel count for an audio track (2 = stereo, 6 = 5.1, 8 = 7.1), nil when unknown.
    public let channels: Int?
    /// Whether the ENGINE currently has this track selected.
    ///
    /// Load-bearing for audio: switching tracks after playback has started tears down and restarts
    /// the decoder, which is an audible drop-out. Knowing what the engine already chose is what
    /// lets the automatic pick leave a perfectly good choice alone instead of "correcting" it.
    public let isSelected: Bool
    public init(id: String, kind: TrackKind, name: String, language: String? = nil,
                isExternal: Bool = false, codec: String? = nil, channels: Int? = nil,
                isSelected: Bool = false) {
        self.id = id
        self.kind = kind
        self.name = name
        self.language = language
        self.isExternal = isExternal
        self.codec = codec
        self.channels = channels
        self.isSelected = isSelected
    }
}

/// What the engine emits over time.
public enum PlaybackEvent: Sendable, Equatable {
    case state(PlaybackState)
    case time(PlaybackTime)
    /// The set of available audio/subtitle tracks changed (the engine discovered an elementary
    /// stream, or an external subtitle was attached). Consumers re-read `audioTracks`/`subtitleTracks`.
    case tracksChanged
}
