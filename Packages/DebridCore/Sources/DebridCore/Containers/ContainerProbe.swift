import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking   // URLSession lives here on Linux
#endif

/// Reads a remote video file's track list from its first bytes, without downloading the file.
///
/// At most two ranged reads: the first 256 KiB, where every common muxer writes the track list,
/// and — only when the file's SeekHead says the list lies further in — 256 KiB from there.
///
/// A server that ignores `Range` would start sending the whole file (a REMUX is 60 GB), so a
/// response is used only when it is `206 Partial Content`, and never read past the window.
public struct ContainerProbe: Sendable {
    public static let window = 262_144

    public enum Outcome: Sendable, Equatable {
        case tracks([ContainerTrack])
        case notMatroska
        /// A Matroska file whose track list could not be found.
        case unreadable
    }

    private let configuration: @Sendable () -> URLSessionConfiguration

    public init(configuration: @escaping @Sendable () -> URLSessionConfiguration = { .ephemeral }) {
        self.configuration = configuration
    }

    /// nil is a transient failure — network, an HTTP error, or a server that ignored `Range`. The
    /// caller must not remember it; the next visit tries again.
    public func tracks(at url: URL) async -> Outcome? {
        let head: [UInt8]
        switch await read(url, from: 0) {
        case .bytes(let bytes, _): head = bytes
        case .pastEnd: return .unreadable            // an empty file
        case .failed: return nil
        }
        switch MatroskaTrackReader.read(head) {
        case .tracks(let tracks):
            return .tracks(tracks)
        case .notMatroska:
            return .notMatroska
        case .incomplete:
            return .unreadable
        case .tracksAt(let offset):
            if offset < head.count,
               let tracks = MatroskaTrackReader.readTracksElement(Array(head[offset...])) {
                return .tracks(tracks)
            }
            switch await read(url, from: offset) {
            case .bytes(let tail, _):
                return MatroskaTrackReader.readTracksElement(tail).map(Outcome.tracks) ?? .unreadable
            case .pastEnd:
                return .unreadable                   // the SeekHead points past the end: a broken file
            case .failed:
                return nil
            }
        }
    }

    // MARK: - The index

    /// The largest index read. The biggest measured was 1.8 MB (a disc with 37 subtitle tracks); a
    /// file claiming far more is corrupt, and is not worth the bandwidth mid-film.
    public static let maxIndexBytes = 16 << 20

    /// The file's own subtitle timetable and chapters, for `FilmEnding`.
    ///
    /// The first window (the layout), then the track list, the chapters and the index, each read
    /// only as far as its own length — a few hundred KB at the end of a 60 GB file. nil when the
    /// file is not Matroska, has no index, or a read fails; the caller falls back, nothing retries.
    public func index(at url: URL) async -> MatroskaIndex? {
        guard case .bytes(let head, let fileSize) = await read(url, from: 0),
              let layout = MatroskaIndexReader.layout(head),
              let tracksAt = layout.tracksAt, let cuesAt = layout.cuesAt
        else { return nil }
        let file = FileRef(url: url, head: head, size: fileSize)
        guard let tracksBytes = await element(MatroskaTrackReader.ID.tracks, at: tracksAt, in: file,
                                              cap: Self.window)
        else { return nil }
        let tracks = MatroskaIndexReader.subtitleTracks(tracksBytes)
        var chapters: [MatroskaIndex.Chapter] = []
        if let chaptersAt = layout.chaptersAt,
           let bytes = await element(MatroskaIndexReader.ID.chapters, at: chaptersAt, in: file,
                                     cap: Self.window) {
            chapters = MatroskaIndexReader.chapters(bytes)
        }
        guard let cuesBytes = await element(MatroskaIndexReader.ID.cues, at: cuesAt, in: file,
                                            cap: Self.maxIndexBytes) else { return nil }
        let ends = MatroskaIndexReader.lineEnds(cuesBytes, timecodeScale: layout.timecodeScale)
        let subtitles = tracks.keys.sorted().compactMap { number -> MatroskaIndex.SubtitleTrack? in
            guard let track = tracks[number] else { return nil }
            return MatroskaIndex.SubtitleTrack(track: track, lineEnds: ends[number] ?? [])
        }
        return MatroskaIndex(subtitles: subtitles, chapters: chapters)
    }

    /// The whole element `id` starting at `offset`: from the first window when it lies inside it,
    /// else one read to learn its length and, when it is longer than that read, one more for the
    /// rest. nil when it is not that element, is longer than `cap`, or a read fails.
    private func element(_ id: UInt32, at offset: Int, in file: FileRef, cap: Int) async -> [UInt8]? {
        let head = file.head
        if offset < head.count,
           let length = MatroskaIndexReader.elementLength(Array(head[offset...]), expecting: id),
           length <= head.count - offset {
            return Array(head[offset..<(offset + length)])
        }
        guard case .bytes(let first, _) = await read(file, from: offset, length: Self.window),
              let length = MatroskaIndexReader.elementLength(first, expecting: id), length <= cap
        else { return nil }
        if length <= first.count { return Array(first.prefix(length)) }
        guard case .bytes(let whole, _) = await read(file, from: offset, length: length),
              whole.count >= length else { return nil }
        return Array(whole.prefix(length))
    }

    /// A file being read: its first window, and its size when the server said.
    private struct FileRef {
        let url: URL
        let head: [UInt8]
        let size: Int?
    }

    /// A read that never asks past the end of the file. Real-Debrid answers a range running past
    /// it with a Content-Length for the whole range, then closes after the bytes that exist — a
    /// "failed" transfer, for exactly the read the index needs, since the index ends the file.
    private func read(_ file: FileRef, from offset: Int, length: Int) async -> RangedReadResult {
        guard let size = file.size else { return await read(file.url, from: offset, length: length) }
        guard offset < size else { return .pastEnd }
        return await read(file.url, from: offset, length: min(length, size - offset))
    }

    private func read(_ url: URL, from offset: Int, length: Int = ContainerProbe.window) async -> RangedReadResult {
        // The offset came out of the file. However it was bounded upstream, the arithmetic here
        // must not be what traps.
        guard offset >= 0, length > 0, offset <= Int.max - length else { return .pastEnd }
        var request = URLRequest(url: url)
        request.setValue("bytes=\(offset)-\(offset + length - 1)", forHTTPHeaderField: "Range")
        let settings = configuration()
        settings.timeoutIntervalForRequest = 15
        // The request timeout is only the longest SILENCE: a server trickling a byte a second
        // would hold one of the few read slots for good.
        settings.timeoutIntervalForResource = 30
        return await RangedRead(cap: length).run(request, configuration: settings)
    }
}

/// What one ranged GET came back with.
private enum RangedReadResult: Sendable {
    /// `fileSize` is the total in the response's Content-Range, when the server sent one.
    case bytes([UInt8], fileSize: Int?)
    /// `416`: the range starts past the end of the file. A fact about the file, not the network.
    case pastEnd
    case failed
}

/// One ranged GET, driven by a delegate so it can refuse a response that is not `206` as soon as
/// its first bytes arrive, and stop at `cap`. `URLSession.data(for:)` does neither: it downloads
/// the whole body before returning, which for a server that ignores `Range` is the whole film.
///
/// Only the two delegate methods that take no completion handler are implemented, so the
/// signatures are identical on Apple platforms and in Linux's FoundationNetworking.
private final class RangedRead: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let cap: Int
    private let lock = NSLock()
    private var buffer: [UInt8] = []
    private var refused = false
    private var continuation: CheckedContinuation<RangedReadResult, Never>?

    init(cap: Int) { self.cap = cap }

    func run(_ request: URLRequest, configuration: URLSessionConfiguration) async -> RangedReadResult {
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        return await withCheckedContinuation { continuation in
            lock.lock()
            self.continuation = continuation
            lock.unlock()
            session.dataTask(with: request).resume()
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let status = (dataTask.response as? HTTPURLResponse)?.statusCode
        lock.lock()
        if status == 206 {
            buffer.append(contentsOf: data)
        } else {
            refused = true
        }
        let stop = refused || buffer.count >= cap
        lock.unlock()
        if stop { dataTask.cancel() }
    }

    /// The total from `Content-Range: bytes 0-262143/37093984052`. nil when absent or "*".
    static func fileSize(of response: URLResponse?) -> Int? {
        guard let header = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Range"),
              let total = header.split(separator: "/").last else { return nil }
        return Int(total.trimmingCharacters(in: .whitespaces))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let status = (task.response as? HTTPURLResponse)?.statusCode
        lock.lock()
        let complete = error == nil || buffer.count >= cap
        let result: RangedReadResult
        if status == 416 {
            result = .pastEnd
        } else if !refused, status == 206, complete {
            result = .bytes(Array(buffer.prefix(cap)), fileSize: Self.fileSize(of: task.response))
        } else {
            result = .failed
        }
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: result)
    }
}
