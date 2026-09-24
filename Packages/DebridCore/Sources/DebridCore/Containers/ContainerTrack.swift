import Foundation

/// One elementary stream, as a file's header (or the player) describes it.
public struct ContainerTrack: Sendable, Equatable, Codable {
    public enum Kind: String, Sendable, Codable { case video, audio, subtitle }

    public let kind: Kind
    /// ISO 639-1 when the file says, nil when it does not.
    public let language: String?
    /// Matroska codec ID ("S_HDMV/PGS") or the player's fourcc ("bdpg").
    public let codec: String?
    public let name: String?
    /// Signs and foreign-dialogue lines only. Not the subtitles a viewer reads the film with.
    public let isForced: Bool
    /// Video only: frames per second, from Matroska's DefaultDuration.
    public let frameRate: Double?

    public init(kind: Kind, language: String?, codec: String? = nil, name: String? = nil,
                isForced: Bool = false, frameRate: Double? = nil) {
        self.kind = kind
        self.language = language
        self.codec = codec
        self.name = name
        self.isForced = isForced
        self.frameRate = frameRate
    }

    /// A subtitle drawn as pictures (Blu-ray PGS, DVD VobSub, DVB) rather than text. Still in sync
    /// with the film, but it ignores font settings and cannot be retimed.
    public var isImageSubtitle: Bool {
        guard kind == .subtitle, let codec else { return false }
        return Self.pictureCodecs.contains(codec.trimmingCharacters(in: .whitespaces).lowercased())
    }

    /// Matroska codec IDs and VLC's fourccs for picture subtitles.
    private static let pictureCodecs: Set<String> = [
        "s_hdmv/pgs", "s_vobsub", "s_dvbsub", "s_image/bmp",
        "bdpg", "pgs", "hdmv", "spu", "spub", "dvbs", "dvds", "xsub", "cvd", "ogt",
    ]
}

public extension ContainerTrack {
    /// A track as the player reports it. The player has no forced flag and no per-track frame
    /// rate; a track with no language tag is named from its label ("Hebrew", "עברית"), and one
    /// labelled "Forced" is taken at its word.
    init(_ track: MediaTrack) {
        self.init(kind: track.kind == .audio ? .audio : .subtitle,
                  language: LanguageCode.normalize(track.language) ?? LanguageCode.fromName(track.name),
                  codec: track.codec, name: track.name,
                  isForced: track.name.range(of: "forced", options: .caseInsensitive) != nil)
    }
}
