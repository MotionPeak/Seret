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
    /// Video only: the transfer function the file's own header declares (Matroska's
    /// `Colour/TransferCharacteristics`), nil when it says nothing usable.
    public let transfer: VideoTransfer?
    /// Video only: bits per sample, from `Colour/BitsPerChannel` or the HEVC decoder configuration;
    /// nil when the header says neither. 8-bit video is never HDR.
    public let bitDepth: Int?

    public init(kind: Kind, language: String?, codec: String? = nil, name: String? = nil,
                isForced: Bool = false, frameRate: Double? = nil, transfer: VideoTransfer? = nil,
                bitDepth: Int? = nil) {
        self.kind = kind
        self.language = language
        self.codec = codec
        self.name = name
        self.isForced = isForced
        self.frameRate = frameRate
        self.transfer = transfer
        self.bitDepth = bitDepth
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

/// How a video's brightness is encoded — what decides whether a TV shows it in SDR or HDR.
public enum VideoTransfer: String, Sendable, Codable {
    /// BT.709 / BT.601 / BT.2020 gamma: standard dynamic range.
    case sdr
    /// SMPTE ST 2084 (PQ): HDR10, HDR10+ and Dolby Vision's HDR10-compatible base layer.
    case pq
    /// ARIB STD-B67: hybrid log-gamma.
    case hlg

    /// From an ISO/IEC 23091-2 `transfer_characteristics` code, as Matroska stores it. nil for
    /// "unspecified" and anything unrecognised.
    public init?(code: UInt64) {
        switch code {
        case 16: self = .pq
        case 18: self = .hlg
        case 1, 4, 5, 6, 7, 8, 13, 14, 15: self = .sdr
        default: return nil
        }
    }
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
