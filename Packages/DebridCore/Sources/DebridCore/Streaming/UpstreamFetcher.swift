import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// One streaming `GET Range: bytes=N-` to Real-Debrid.
///
/// Open-ended, like libvlc's own requests: RD answers `Connection: close`, so every request is a new
/// TCP + TLS connection (~460ms measured) and one long stream is far cheaper than many short ones.
/// Events come out of `events` in order — an AsyncStream preserves the delegate's order, which
/// separate Tasks per callback would not.
final class UpstreamFetcher: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    enum Event: Sendable {
        case response(status: Int, totalSize: Int64?, contentType: String?)
        case data(Data)
        case finished(StreamError?)
    }

    let events: AsyncStream<Event>
    private let continuation: AsyncStream<Event>.Continuation
    private let request: URLRequest
    private let configuration: URLSessionConfiguration
    private let lock = NSLock()
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var cancelled = false

    init(url: URL, start: Int64, configuration: URLSessionConfiguration) {
        var request = URLRequest(url: url)
        request.setValue("bytes=\(start)-", forHTTPHeaderField: "Range")
        self.request = request
        self.configuration = configuration
        (events, continuation) = AsyncStream.makeStream(of: Event.self, bufferingPolicy: .unbounded)
        super.init()
    }

    func start() {
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        let task = session.dataTask(with: request)
        lock.lock(); self.session = session; self.task = task; lock.unlock()
        task.resume()
    }

    /// Backpressure: stop reading the socket (the read-ahead cap is reached). RD may drop an idle
    /// connection; the session then starts a new fetch when it needs the bytes.
    func suspend() { currentTask()?.suspend() }
    func resume() { currentTask()?.resume() }

    func cancel() {
        lock.lock()
        cancelled = true
        let session = self.session, task = self.task
        lock.unlock()
        task?.cancel()
        session?.invalidateAndCancel()
        continuation.finish()
    }

    private func currentTask() -> URLSessionDataTask? {
        lock.lock(); defer { lock.unlock() }
        return task
    }

    // MARK: - URLSessionDataDelegate

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        let http = response as? HTTPURLResponse
        let status = http?.statusCode ?? 0
        continuation.yield(.response(status: status,
                                     totalSize: http.flatMap(Self.totalSize(from:)),
                                     contentType: http?.value(forHTTPHeaderField: "Content-Type")))
        completionHandler((200...299).contains(status) ? .allow : .cancel)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        continuation.yield(.data(data))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock(); let wasCancelled = cancelled; lock.unlock()
        let failure: StreamError? = (error == nil || wasCancelled) ? nil
            : .transport((error as NSError?)?.localizedDescription ?? "unknown")
        continuation.yield(.finished(failure))
        continuation.finish()
        session.finishTasksAndInvalidate()
    }

    /// The file's full size: from `Content-Range: bytes a-b/TOTAL`, or a 200's length.
    static func totalSize(from response: HTTPURLResponse) -> Int64? {
        if let range = response.value(forHTTPHeaderField: "Content-Range"),
           let slash = range.lastIndex(of: "/") {
            return Int64(range[range.index(after: slash)...].trimmingCharacters(in: .whitespaces))
        }
        if response.statusCode == 200, response.expectedContentLength > 0 {
            return response.expectedContentLength
        }
        return nil
    }
}
