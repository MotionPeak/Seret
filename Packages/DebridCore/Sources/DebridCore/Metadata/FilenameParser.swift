import Foundation

/// Turns a release filename into a `ParsedRelease`. Pure and dependency-free.
/// Metadata fields are matched by regex on the original (dotted) name; the title is
/// the run of leading tokens before the first metadata token.
public struct FilenameParser: Sendable {
    public init() {}

    public func parse(_ raw: String) -> ParsedRelease {
        let name = String(raw.split(separator: "/").last ?? Substring(raw))
        let stem = Self.stripExtension(name)

        let releaseGroup = Self.capture(stem, #"-([A-Za-z0-9]{2,})$"#)
        let resolution = Self.match(stem, #"(?i)\b(2160p|1080p|720p|480p)\b"#).map { $0.lowercased() }
        let source = Self.normalizeSource(Self.match(stem, #"(?i)\b(blu-?ray|bd-?rip|web-?dl|web-?rip|hdtv|dvd-?rip|remux|hdrip)\b"#))
        let videoCodec = Self.normalizeVideo(Self.match(stem, #"(?i)\b(x265|x264|h\.?265|h\.?264|hevc|avc)\b"#))
        let audioCodec = Self.normalizeAudio(Self.match(stem, #"(?i)\b(dts-?hd|truehd|atmos|ddp?5\.1|ddp|dts|eac3|ac3|aac|flac)\b"#))
        let year = Self.match(stem, #"\b(19\d{2}|20\d{2})\b"#).flatMap { Int($0) }

        var season: Int?
        var episode: Int?
        if let g = Self.captures(stem, #"(?i)\bS(\d{1,2})E(\d{1,3})\b"#) {
            season = Int(g[0]); episode = Int(g[1])
        } else if let g = Self.captures(stem, #"(?i)\b(\d{1,2})x(\d{1,3})\b"#) {
            season = Int(g[0]); episode = Int(g[1])
        } else if let g = Self.captures(stem, #"(?i)\bseason\s?(\d{1,2})\b"#) {
            season = Int(g[0])
        } else if let g = Self.captures(stem, #"(?i)\bS(\d{1,2})\b"#) {
            season = Int(g[0])
        }

        return ParsedRelease(
            title: Self.extractTitle(stem),
            year: year, season: season, episode: episode,
            resolution: resolution, source: source, videoCodec: videoCodec,
            audioCodec: audioCodec, releaseGroup: releaseGroup)
    }

    // MARK: - Title

    private static func extractTitle(_ stem: String) -> String {
        let tokens = stem.split(whereSeparator: { $0 == "." || $0 == "_" || $0 == " " }).map(String.init)
        var titleTokens: [String] = []
        for token in tokens {
            if isMetadataToken(token) { break }
            titleTokens.append(token)
        }
        let joined = titleTokens.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return joined.isEmpty ? stem : joined
    }

    private static func isMetadataToken(_ t: String) -> Bool {
        let patterns = [
            #"^(19|20)\d{2}$"#,
            #"(?i)^s\d{1,2}e\d{1,3}$"#,
            #"(?i)^s\d{1,2}$"#,
            #"(?i)^\d{1,2}x\d{1,3}$"#,
            #"(?i)^(2160p|1080p|720p|480p)$"#,
            #"(?i)^season$"#,
            #"(?i)^(bluray|blu-ray|bdrip|web-?dl|web-?rip|hdtv|dvdrip|remux|hdrip|x265|x264|h264|h265|hevc|avc|amzn|uhd|hdr)$"#,
        ]
        return patterns.contains { t.range(of: $0, options: .regularExpression) != nil }
    }

    // MARK: - Normalization (canonical display forms)

    private static func normalizeSource(_ s: String?) -> String? {
        guard let s = s?.lowercased() else { return nil }
        if s.hasPrefix("blu") { return "BluRay" }
        if s.replacingOccurrences(of: "-", with: "") == "webdl" { return "WEB-DL" }
        if s.replacingOccurrences(of: "-", with: "") == "webrip" { return "WEBRip" }
        if s.contains("remux") { return "REMUX" }
        if s.contains("hdtv") { return "HDTV" }
        if s.contains("bd") { return "BDRip" }
        if s.contains("dvd") { return "DVDRip" }
        if s.contains("hdrip") { return "HDRip" }
        return s.uppercased()
    }

    private static func normalizeVideo(_ s: String?) -> String? {
        guard let s = s?.lowercased().replacingOccurrences(of: ".", with: "") else { return nil }
        switch s {
        case "x265": return "x265"
        case "x264": return "x264"
        case "hevc": return "HEVC"
        case "h265": return "h265"
        case "avc": return "AVC"
        case "h264": return "h264"
        default: return s
        }
    }

    private static func normalizeAudio(_ s: String?) -> String? {
        guard let raw = s else { return nil }
        let s = raw.lowercased()
        if s.replacingOccurrences(of: "-", with: "") == "dtshd" { return "DTS-HD" }
        if s.hasPrefix("ddp") { return "DDP5.1" }
        if s == "truehd" { return "TrueHD" }
        if s == "atmos" { return "Atmos" }
        if s == "eac3" { return "EAC3" }
        if s == "ac3" { return "AC3" }
        if s == "aac" { return "AAC" }
        if s == "flac" { return "FLAC" }
        if s == "dts" { return "DTS" }
        return raw.uppercased()
    }

    // MARK: - Regex helpers

    private static func stripExtension(_ s: String) -> String {
        let exts: Set<String> = ["mkv", "mp4", "avi", "m4v", "mov", "ts", "wmv", "srt", "ass"]
        guard let dot = s.range(of: #"\.[A-Za-z0-9]{2,4}$"#, options: .regularExpression) else { return s }
        let ext = s[dot].dropFirst().lowercased()
        return exts.contains(String(ext)) ? String(s[s.startIndex..<dot.lowerBound]) : s
    }

    private static func match(_ s: String, _ pattern: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              let r = Range(m.range, in: s) else { return nil }
        return String(s[r])
    }

    private static func capture(_ s: String, _ pattern: String) -> String? {
        captures(s, pattern)?.first
    }

    private static func captures(_ s: String, _ pattern: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              m.numberOfRanges > 1 else { return nil }
        var groups: [String] = []
        for i in 1..<m.numberOfRanges {
            guard let r = Range(m.range(at: i), in: s) else { return nil }
            groups.append(String(s[r]))
        }
        return groups
    }
}
