import Foundation

/// Probes a media URL with ffprobe and decides whether the browser can play it as-is.
/// Direct-play skips ffmpeg entirely — no CPU, no HLS, instant start.
struct MediaProbe: Sendable, Equatable {
    enum Decision: Sendable, Equatable { case direct, transcode }

    let container: String
    let videoCodec: String?
    let audioCodec: String?

    /// Browsers reliably play only H.264 video with AAC/MP3 audio inside MP4/MOV. Anything else
    /// (MKV/Matroska, HEVC, DTS/TrueHD, VC-1) has to go through ffmpeg.
    var decision: Decision {
        let containers = container.split(separator: ",").map(String.init)
        let containerOK = containers.contains { ["mp4", "mov", "m4a", "3gp"].contains($0) }
        guard containerOK,
              videoCodec == "h264",
              let audio = audioCodec, ["aac", "mp3"].contains(audio)
        else { return .transcode }
        return .direct
    }

    private struct FFProbeOutput: Decodable {
        struct Format: Decodable { let format_name: String? }
        struct Stream: Decodable { let codec_type: String?; let codec_name: String? }
        let format: Format?
        let streams: [Stream]?
    }

    static func parse(_ data: Data) throws -> MediaProbe {
        let out = try JSONDecoder().decode(FFProbeOutput.self, from: data)
        let streams = out.streams ?? []
        return MediaProbe(
            container: out.format?.format_name ?? "",
            videoCodec: streams.first { $0.codec_type == "video" }?.codec_name,
            audioCodec: streams.first { $0.codec_type == "audio" }?.codec_name
        )
    }

    /// Run ffprobe against a URL. Returns nil when ffprobe is unavailable or fails — callers
    /// treat nil as "transcode", which is always safe.
    static func probe(url: String) async -> MediaProbe? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ffprobe")
        p.arguments = ["-v", "quiet", "-print_format", "json", "-show_format", "-show_streams",
                       "-analyzeduration", "5M", "-probesize", "5M", url]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        return try? parse(data)
    }
}
