import Foundation
import Testing
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Serialized parent for every suite that touches RangeFileURLProtocol's shared state (same
/// pattern as MockTests): Swift Testing runs separate suites in parallel otherwise.
@Suite(.serialized)
struct StreamingNetworkTests {}

/// A fake Real-Debrid download server: one synthetic file whose byte at offset i is a fixed
/// function of i, so any slice can be checked exactly. Honours `Range: bytes=N-`, answers 206 with
/// a Content-Range, and streams in pieces on a background queue until stopped.
final class RangeFileURLProtocol: URLProtocol, @unchecked Sendable {
    /// How one request can go wrong instead of being served.
    enum Fault: Sendable {
        /// No HTTP at all: the network is down, or the connection dropped.
        case transport(URLError.Code)
        /// This status and no body — RD busy (429), a server fault (5xx).
        case status(Int)
        /// The Range header ignored: a 200 with the whole file, from byte 0.
        case wholeFile
    }

    struct Stub: Sendable {
        var fileSize: Int64 = 64 << 20
        var piece = 64 << 10
        /// Bytes one request delivers before the "connection" ends — RD responses can end early.
        var maxBytesPerRequest: Int64 = .max
        /// A status per URL path (e.g. 403 for an expired link). Everything else is 206.
        var statusByPath: [String: Int] = [:]
        /// Seconds the answer to a request from this byte waits before it arrives: RD answering
        /// one connection late, after another.
        var delayByStart: [Int64: TimeInterval] = [:]
        /// What happens to the first requests, in the order they arrive; the rest are served.
        var faults: [Fault] = []
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var current = Stub()
    nonisolated(unsafe) private static var log: [(path: String, start: Int64)] = []

    static func reset(_ stub: Stub = Stub()) {
        lock.lock(); current = stub; log = []; lock.unlock()
    }
    static var stub: Stub { lock.lock(); defer { lock.unlock() }; return current }
    static var requests: [(path: String, start: Int64)] { lock.lock(); defer { lock.unlock() }; return log }

    static func byte(at i: Int64) -> UInt8 { UInt8(truncatingIfNeeded: (i &* 2_654_435_761) >> 11) }
    static func bytes(_ range: Range<Int64>) -> Data { Data(range.map(byte(at:))) }

    static var configuration: URLSessionConfiguration {
        let c = URLSessionConfiguration.ephemeral
        c.protocolClasses = [RangeFileURLProtocol.self]
        return c
    }

    private let stopLock = NSLock()
    private var stopped = false
    private var isStopped: Bool { stopLock.lock(); defer { stopLock.unlock() }; return stopped }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let stub = Self.stub
        let url = request.url!
        let range = request.value(forHTTPHeaderField: "Range") ?? "bytes=0-"
        let start = Int64(range.dropFirst("bytes=".count).split(separator: "-").first ?? "0") ?? 0
        Self.lock.lock()
        let fault = Self.log.count < stub.faults.count ? stub.faults[Self.log.count] : nil
        Self.log.append((url.path, start))
        Self.lock.unlock()

        guard let delay = stub.delayByStart[start] else {
            return answer(stub, url: url, start: start, fault: fault)
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [self] in
            if !isStopped { answer(stub, url: url, start: start, fault: fault) }
        }
    }

    private func answer(_ stub: Stub, url: URL, start: Int64, fault: Fault?) {
        switch fault {
        case .transport(let code)?:
            client?.urlProtocol(self, didFailWithError: URLError(code))
        case .status(let status)?:
            refuse(url, status: status)
        case .wholeFile?:
            stream(stub, url: url, status: 200, from: 0, headers: [
                "Content-Length": "\(stub.fileSize)",
                "Content-Type": "application/force-download"])
        case nil:
            let status = stub.statusByPath[url.path] ?? 206
            guard status == 206 else { return refuse(url, status: status) }
            stream(stub, url: url, status: 206, from: start, headers: [
                "Content-Range": "bytes \(start)-\(stub.fileSize - 1)/\(stub.fileSize)",
                "Content-Length": "\(stub.fileSize - start)",
                "Content-Type": "application/force-download",
                "Accept-Ranges": "bytes"])
        }
    }

    private func refuse(_ url: URL, status: Int) {
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Length": "0"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }

    private func stream(_ stub: Stub, url: URL, status: Int, from start: Int64, headers: [String: String]) {
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
                                       headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        let limit = stub.maxBytesPerRequest >= stub.fileSize
            ? stub.fileSize : min(stub.fileSize, start + stub.maxBytesPerRequest)
        DispatchQueue.global().async { [self] in
            var cursor = start
            while cursor < limit, !isStopped {
                let next = min(limit, cursor + Int64(stub.piece))
                client?.urlProtocol(self, didLoad: Self.bytes(cursor..<next))
                cursor = next
                usleep(200)
            }
            if !isStopped { client?.urlProtocolDidFinishLoading(self) }
        }
    }

    override func stopLoading() {
        stopLock.lock(); stopped = true; stopLock.unlock()
    }
}
