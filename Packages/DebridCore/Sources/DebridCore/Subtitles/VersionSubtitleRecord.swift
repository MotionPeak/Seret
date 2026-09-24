import Foundation

/// What is known about one owned file's own subtitles and audio. Keyed by `WatchKey.source`.
///
/// A file's content never changes, so a record is kept for good. It comes from reading the file's
/// header, from what the player saw while it played, or both.
public struct VersionSubtitleRecord: Sendable, Equatable, Codable {
    public enum Origin: String, Sendable, Codable {
        /// Read from the file's first bytes.
        case header
        /// Reported by the player (folded over any header read).
        case playback
        /// Not something the header reader understands (MP4, AVI). Nothing more to learn by reading.
        case unreadable
    }

    public var origin: Origin
    /// The file name Real-Debrid reports. Release-name tags ("HebSubs") live here.
    public var fileName: String?
    public var tracks: [ContainerTrack]

    public init(origin: Origin, fileName: String? = nil, tracks: [ContainerTrack] = []) {
        self.origin = origin
        self.fileName = fileName
        self.tracks = tracks
    }

    /// Hebrew in this file, from its tracks and its name.
    public var hebrewLevel: HebrewSubtitles {
        if let fileName, ReleaseSubtitleTags().scan(fileName).languages.contains("he") { return .builtIn }
        let hebrew = tracks.filter { $0.kind == .subtitle && $0.language == "he" && !$0.isForced }
        if hebrew.contains(where: { !$0.isImageSubtitle }) { return .builtIn }
        return hebrew.isEmpty ? .none : .builtInImage
    }

    /// The file's audio languages in order, nil when none is tagged.
    public var audioLanguages: [String]? {
        var seen: [String] = []
        for track in tracks where track.kind == .audio {
            if let code = track.language, !seen.contains(code) { seen.append(code) }
        }
        return seen.isEmpty ? nil : seen
    }

    public var frameRate: Double? { tracks.first { $0.kind == .video }?.frameRate }

    /// This record with what the player saw folded in. A union, not a replacement: the player
    /// announces tracks one at a time, so a report written early in a play can be partial, and
    /// dropping a header-read track the player had not reported yet would lose it.
    public func merging(playback observed: [ContainerTrack]) -> VersionSubtitleRecord {
        var merged = tracks
        for track in observed where !merged.contains(track) { merged.append(track) }
        return VersionSubtitleRecord(origin: .playback, fileName: fileName, tracks: merged)
    }
}
