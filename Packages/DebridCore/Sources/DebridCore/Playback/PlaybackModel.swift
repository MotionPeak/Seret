import Foundation

/// The lifecycle of a playback session, as the engine reports it.
public enum PlaybackState: Sendable, Equatable {
    case idle, buffering, playing, paused, ended
    case failed(String)
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
    public init(id: String, kind: TrackKind, name: String, language: String? = nil,
                isExternal: Bool = false, codec: String? = nil, channels: Int? = nil) {
        self.id = id
        self.kind = kind
        self.name = name
        self.language = language
        self.isExternal = isExternal
        self.codec = codec
        self.channels = channels
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
