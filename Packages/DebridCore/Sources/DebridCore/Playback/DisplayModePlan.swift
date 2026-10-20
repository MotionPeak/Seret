import Foundation

/// The display mode a video should be shown in: its frame rate and its dynamic range.
///
/// The Apple TV only leaves its interface mode (typically 2160p 60 Hz) when the app asks, with
/// `AVDisplayManager.preferredDisplayCriteria` — AVPlayer does that for itself, a libvlc app has
/// to do it on its own, and Seret never did. So 23.976 fps films played in a 60 Hz mode: on the
/// Apple TV's own log a 2160p HEVC HDR10 remux dropped 2 pictures every second, each one frame
/// period late, for the whole film (QA sweep 2026-10-20, §2c) — and the owner's "Match Content"
/// setting could not take effect for Seret at all.
///
/// Pure, so the rules are tested here; the tvOS player turns a plan into display criteria. The
/// system still decides: with "Match Content" off in Settings the request is simply ignored.
public struct DisplayModePlan: Sendable, Equatable {
    public enum Range: String, Sendable, Equatable {
        case sdr
        /// PQ. Dolby Vision is asked for as HDR10 too: libvlc renders the HDR10-compatible base
        /// layer and passes no Dolby Vision metadata, so a Dolby Vision mode would gain nothing.
        case hdr10
        case hlg
    }

    /// The refresh rate to ask for, in Hz; nil while the frame rate is not known yet.
    public let refreshRate: Double?
    public let range: Range

    public init(refreshRate: Double?, range: Range) {
        self.refreshRate = refreshRate
        self.range = range
    }

    /// The plan for a file, from what its header says and, failing that, its name. nil when the
    /// dynamic range cannot be told: asking for the wrong one (SDR for an HDR film) would be worse
    /// than leaving the display alone, so an unknown is left exactly as it was.
    public static func plan(video: ContainerTrack?, fileName: String) -> DisplayModePlan? {
        guard let range = range(transfer: video?.transfer, codec: video?.codec, fileName: fileName)
        else { return nil }
        return DisplayModePlan(refreshRate: video?.frameRate.flatMap(refreshRate(forFPS:)), range: range)
    }

    /// The same plan with the frame rate the player reported, once it did.
    public func with(fps: Double?) -> DisplayModePlan {
        DisplayModePlan(refreshRate: fps.flatMap(Self.refreshRate(forFPS:)) ?? refreshRate, range: range)
    }

    /// The dynamic range: the header's transfer function first; an AVC video is SDR (nothing
    /// ships HDR in AVC); then the release name's tags. nil when none of them says.
    public static func range(transfer: VideoTransfer?, codec: String?, fileName: String) -> Range? {
        switch transfer {
        case .pq?: return .hdr10
        case .hlg?: return .hlg
        case .sdr?: return .sdr
        case nil: break
        }
        if let codec, codec.uppercased().hasPrefix("V_MPEG4/ISO/AVC") { return .sdr }
        let name = fileName.lowercased()
        if name.range(of: Self.hlgTag, options: .regularExpression) != nil { return .hlg }
        if name.range(of: Self.hdrTag, options: .regularExpression) != nil { return .hdr10 }
        if name.range(of: Self.sdrTag, options: .regularExpression) != nil { return .sdr }
        return nil
    }

    private static let separator = #"(^|[\s._\-\[\]()+])"#
    private static let end = #"([\s._\-\[\]()+]|$)"#
    private static let hdrTag = separator + #"(hdr|hdr10|hdr10\+|hdr10plus|dv|dovi|dolby[\s._]?vision)"# + end
    private static let hlgTag = separator + "hlg" + end
    private static let sdrTag = separator + "sdr" + end

    /// The broadcast rates a TV actually offers. A frame rate within a whisker of one is that
    /// one — DefaultDuration is rounded to whole nanoseconds, so 23.976 arrives as 23.976023…
    static let standardRates: [Double] = [24000.0 / 1001, 24, 25, 30000.0 / 1001, 30,
                                          48000.0 / 1001, 48, 50, 60000.0 / 1001, 60]

    /// The refresh rate for a frame rate: the standard rate it is, or the rate itself when it is
    /// a plausible one; nil for anything a display would not run at.
    public static func refreshRate(forFPS fps: Double) -> Double? {
        guard fps.isFinite, fps >= 10, fps <= 120 else { return nil }
        if let standard = standardRates.first(where: { abs($0 - fps) < 0.02 }) { return standard }
        return fps
    }
}
