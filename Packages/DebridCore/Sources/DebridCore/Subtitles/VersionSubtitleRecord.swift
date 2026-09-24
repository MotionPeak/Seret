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

    /// The file's audio languages in order — nil unless EVERY audio track is tagged.
    ///
    /// An untagged track could be the film's own language, and then nothing can be said about a
    /// dub. Listing only the tagged ones made a real release (untagged English, then French and
    /// Spanish) look like it had lost its original audio.
    public var audioLanguages: [String]? {
        let audio = tracks.filter { $0.kind == .audio }
        guard !audio.isEmpty, audio.allSatisfy({ $0.language != nil }) else { return nil }
        var seen: [String] = []
        for code in audio.compactMap(\.language) where !seen.contains(code) { seen.append(code) }
        return seen
    }

    public var frameRate: Double? { tracks.first { $0.kind == .video }?.frameRate }

    /// This record with what the player saw folded in.
    ///
    /// A header read is the file's own index and is kept exactly as read: the player reports the
    /// same tracks with less detail — no forced flag, a fourcc for a codec — and appending its
    /// copies turned a forced-only Hebrew track into "Built in" after a single play. So playback
    /// only teaches something about a file the header could not read (an MP4) or never read.
    ///
    /// For those it is a union, not a replacement: the player announces tracks one at a time, and
    /// an early, partial report must not erase an earlier, fuller one.
    public func merging(playback observed: [ContainerTrack]) -> VersionSubtitleRecord {
        guard origin != .header else { return self }
        var merged = tracks
        for track in observed where !merged.contains(track) { merged.append(track) }
        return VersionSubtitleRecord(origin: .playback, fileName: fileName, tracks: merged)
    }
}
