import Foundation

/// Owns ffmpeg (VAAPI) processes that transcode an unrestricted RD URL into HLS on disk.
/// One session per play. Skeleton policy: ALWAYS transcode (direct-play detection is Plan 2).
actor TranscodeManager {
    struct Session { let id: String; let dir: URL; let process: Process }

    private var sessions: [String: Session] = [:]
    private let root: URL
    private let maxHeight: Int
    private let maxSessions: Int
    private let renderNode: String

    init(root: String, maxHeight: Int, maxSessions: Int,
         renderNode: String = "/dev/dri/renderD128") {
        self.root = URL(fileURLWithPath: root)
        self.maxHeight = maxHeight
        self.maxSessions = maxSessions
        self.renderNode = renderNode
    }

    /// Pure, testable arg builder (no side effects).
    static func ffmpegArgs(input: String, outDir: String, maxHeight: Int,
                           renderNode: String = "/dev/dri/renderD128", seek: Int = 0) -> [String] {
        var a: [String] = []
        if seek > 0 { a += ["-ss", String(seek)] }
        a += [
            "-hwaccel", "vaapi", "-hwaccel_device", renderNode,
            "-hwaccel_output_format", "vaapi",
            "-i", input,
            // format=nv12 is load-bearing. 10-bit HEVC (Main10) decodes to a P010 surface, but
            // h264_vaapi on Gemini Lake only encodes 8-bit, so without this the encoder dies
            // instantly with "No usable encoding profile found". Converting during the VAAPI
            // scale keeps everything on the GPU. (HDR sources look flat until we add tone-mapping
            // — playing beats not playing.)
            "-vf", "scale_vaapi=w=-2:h=min(\(maxHeight)\\,ih):format=nv12",
            "-c:v", "h264_vaapi", "-b:v", "8M", "-maxrate", "10M",
            "-c:a", "aac", "-ac", "2", "-b:a", "192k",
            "-f", "hls", "-hls_time", "4",
            "-hls_flags", "delete_segments+append_list+independent_segments",
            "-hls_playlist_type", "event",
            "-hls_segment_filename", "\(outDir)/seg_%05d.ts",
            "\(outDir)/index.m3u8",
        ]
        return a
    }

    enum TranscodeError: Error { case tooManySessions, ffmpegDiedEarly }

    /// Start a transcode; returns the session id once the manifest file exists (polls up to ~15s).
    func start(input: String) async throws -> String {
        let active = sessions.values.filter { $0.process.isRunning }.count
        guard active < maxSessions else { throw TranscodeError.tooManySessions }

        let id = "S" + UUID().uuidString.prefix(8)
        let dir = root.appendingPathComponent(String(id))
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ffmpeg")
        p.arguments = ["-y", "-loglevel", "error"] + Self.ffmpegArgs(
            input: input, outDir: dir.path, maxHeight: maxHeight, renderNode: renderNode)
        p.standardError = FileHandle.standardError
        try p.run()
        sessions[String(id)] = Session(id: String(id), dir: dir, process: p)

        let manifest = dir.appendingPathComponent("index.m3u8")
        for _ in 0..<75 {   // ~15s
            if FileManager.default.fileExists(atPath: manifest.path) { return String(id) }
            if !p.isRunning { throw TranscodeError.ffmpegDiedEarly }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        return String(id)
    }

    func fileURL(session: String, relativePath: String) -> URL? {
        guard sessions[session] != nil else { return nil }
        let safe = relativePath.split(separator: "/").filter { $0 != ".." }.joined(separator: "/")
        return root.appendingPathComponent(session).appendingPathComponent(safe)
    }

    func stop(session: String) {
        guard let s = sessions.removeValue(forKey: session) else { return }
        if s.process.isRunning { s.process.terminate() }
        try? FileManager.default.removeItem(at: s.dir)
    }
}
