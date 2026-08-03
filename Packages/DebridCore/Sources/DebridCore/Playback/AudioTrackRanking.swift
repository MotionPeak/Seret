import Foundation

/// How reliably tvOS + VLCKit render an audio codec.
///
/// Video is hardware-decoded (VideoToolbox) while audio is software-decoded by libvlc. That
/// asymmetry is the whole reason this type exists: a bad audio pick surfaces as dropouts — or
/// silence — over a perfectly smooth picture, which reads as "the audio is broken" rather than
/// "the machine is struggling". So the codec, not the track's position in the file, decides.
///
/// It matters because a REMUX lists its lossless track FIRST (TrueHD Atmos / DTS-HD MA) and puts
/// the AC-3 compatibility track below it. "First English track" therefore picked the one codec
/// least likely to play.
public enum AudioDecodeTier: Int, Sendable, Comparable {
    /// AAC / AC-3 / E-AC-3 / MP3 / Opus / Vorbis / FLAC / PCM — cheap and dependable.
    case reliable = 0
    /// Unrecognised or untagged: no reason to prefer it, no reason to demote it.
    case unknown = 1
    /// DTS. libvlc decodes the core and drops the HD extensions; 7.1 is heavy enough to break up
    /// on older hardware.
    case heavy = 2
    /// TrueHD / MLP (Atmos) — the most expensive to decode and the likeliest to yield silence.
    case unreliable = 3

    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

public extension MediaTrack {

    /// Four-character codes that decode dependably on tvOS.
    private static let reliableCodecs: Set<String> = [
        "mp4a", "aac", "a52", "ac3", "eac3", "ec-3", "mpga", "mp3", "opus", "vorb", "vorbis",
        "flac", "alac", "araw", "lpcm", "pcm", "twos", "sowt", "in24", "fl32",
    ]
    /// DTS in all its container spellings — decodable, but core-only and expensive.
    private static let heavyCodecs: Set<String> = ["dts", "dtse", "dtsc", "dtsh", "dtsl"]
    /// Dolby TrueHD / MLP.
    private static let unreliableCodecs: Set<String> = ["trhd", "mlp", "truehd", "mlpa"]

    /// This track's decode tier. Unknown when the engine reported no codec.
    var audioDecodeTier: AudioDecodeTier {
        let key = (codec ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        guard !key.isEmpty else { return .unknown }
        if Self.unreliableCodecs.contains(key) { return .unreliable }
        if Self.heavyCodecs.contains(key) { return .heavy }
        if Self.reliableCodecs.contains(key) { return .reliable }
        return .unknown
    }

    /// Whether this track is in `language`.
    ///
    /// Containers spell the tag as "en", "eng", "en-US" or "English" depending on the muxer, so
    /// compare the first two letters of the base subtag. That is exact for the languages this app
    /// selects (English, Hebrew). It is deliberately NOT a general ISO-639-2→639-1 mapping —
    /// Spanish "spa" and "es" would not meet.
    func matchesLanguage(_ language: String) -> Bool {
        guard let mine = self.language else { return false }
        return Self.languageStem(mine) == Self.languageStem(language)
    }

    private static func languageStem(_ tag: String) -> String {
        let base = tag.lowercased().split(separator: "-").first.map(String.init) ?? ""
        return String(base.prefix(2))
    }
}

public extension Array where Element == MediaTrack {

    /// The audio tracks, most-likely-to-actually-play first.
    ///
    /// Stable within a tier: a file's own order is the author's intent (main mix first, commentary
    /// later), so equal-tier tracks must not be reshuffled. `sorted(by:)` gives no stability
    /// guarantee, hence the explicit index tie-break.
    func mostDecodableFirst() -> [MediaTrack] {
        filter { $0.kind == .audio }
            .enumerated()
            .sorted { a, b in
                let left = a.element.audioDecodeTier, right = b.element.audioDecodeTier
                return left == right ? a.offset < b.offset : left < right
            }
            .map(\.element)
    }

    /// The best-playing audio track in `language`, or nil when the media carries none.
    func bestAudio(forLanguage language: String) -> MediaTrack? {
        mostDecodableFirst().first { $0.matchesLanguage(language) }
    }
}
