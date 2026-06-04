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
    public init(id: String, kind: TrackKind, name: String, language: String? = nil) {
        self.id = id
        self.kind = kind
        self.name = name
        self.language = language
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
