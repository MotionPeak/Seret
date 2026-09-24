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
        case .bytes(let bytes): head = bytes
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
            case .bytes(let tail):
                return MatroskaTrackReader.readTracksElement(tail).map(Outcome.tracks) ?? .unreadable
            case .pastEnd:
                return .unreadable                   // the SeekHead points past the end: a broken file
            case .failed:
                return nil
            }
        }
    }

    private func read(_ url: URL, from offset: Int) async -> RangedReadResult {
        // The offset came out of the file. However it was bounded upstream, the arithmetic here
        // must not be what traps.
        guard offset >= 0, offset <= Int.max - Self.window else { return .pastEnd }
        var request = URLRequest(url: url)
        request.setValue("bytes=\(offset)-\(offset + Self.window - 1)", forHTTPHeaderField: "Range")
        let settings = configuration()
        settings.timeoutIntervalForRequest = 15
        // The request timeout is only the longest SILENCE: a server trickling a byte a second
        // would hold one of the few read slots for good.
        settings.timeoutIntervalForResource = 30
        return await RangedRead(cap: Self.window).run(request, configuration: settings)
    }
}

/// What one ranged GET came back with.
private enum RangedReadResult: Sendable {
    case bytes([UInt8])
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

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let status = (task.response as? HTTPURLResponse)?.statusCode
        lock.lock()
        let complete = error == nil || buffer.count >= cap
        let result: RangedReadResult
        if status == 416 {
            result = .pastEnd
        } else if !refused, status == 206, complete {
            result = .bytes(Array(buffer.prefix(cap)))
        } else {
            result = .failed
        }
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: result)
    }
}
