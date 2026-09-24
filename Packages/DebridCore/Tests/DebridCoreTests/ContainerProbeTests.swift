import Testing
import Foundation
@testable import DebridCore

extension MockTests {
    @Suite struct ContainerProbeTests {
        init() { MockURLProtocol.handler = nil }

        /// The Range headers the probe sent, collected off URLSession's thread.
        final class RangeLog: @unchecked Sendable {
            private let lock = NSLock()
            private var ranges: [String] = []
            func add(_ range: String?) { lock.lock(); ranges.append(range ?? ""); lock.unlock() }
            var all: [String] { lock.lock(); defer { lock.unlock() }; return ranges }
        }

        private func probe() -> ContainerProbe {
            ContainerProbe(configuration: {
                let configuration = URLSessionConfiguration.ephemeral
                configuration.protocolClasses = [MockURLProtocol.self]
                return configuration
            })
        }

        private let url = URL(string: "https://example.download.real-debrid.com/d/ABC/Movie.mkv")!

        /// Serves `file` honouring `Range`, as Real-Debrid's download servers do.
        private static func serve(_ file: [UInt8], log: RangeLog, status: Int = 206)
            -> (URLRequest) throws -> (HTTPURLResponse, Data) {
            { request in
                let range = request.value(forHTTPHeaderField: "Range")
                log.add(range)
                let bounds = (range ?? "").replacingOccurrences(of: "bytes=", with: "")
                    .split(separator: "-").compactMap { Int($0) }
                let start = status == 206 ? (bounds.first ?? 0) : 0
                let end = status == 206 ? min(bounds.count > 1 ? bounds[1] : file.count - 1, file.count - 1)
                                        : file.count - 1
                let body = start <= end ? Data(file[start...end]) : Data()
                let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
                                               headerFields: nil)!
                return (response, body)
            }
        }

        @Test func readsTheTrackListFromTheFirstWindow() async {
            let log = RangeLog()
            let file = EBML.file(tracks: [EBML.Track(type: 17, language: "heb")])
            MockURLProtocol.handler = Self.serve(file, log: log)
            let outcome = await probe().tracks(at: url)
            #expect(outcome == .tracks([ContainerTrack(kind: .subtitle, language: "he", codec: "S_TEXT/UTF8")]))
            #expect(log.all == ["bytes=0-262143"])
        }

        @Test func followsTheSeekHeadOnceWhenTheTracksLieFurtherIn() async {
            let log = RangeLog()
            let file = EBML.file(tracks: [EBML.Track(type: 17, language: "heb")], padding: 300_000,
                                 seekHead: true)
            MockURLProtocol.handler = Self.serve(file, log: log)
            let outcome = await probe().tracks(at: url)
            #expect(outcome == .tracks([ContainerTrack(kind: .subtitle, language: "he", codec: "S_TEXT/UTF8")]))
            #expect(log.all.count == 2)
            #expect(log.all.first == "bytes=0-262143")
        }

        @Test func aServerThatIgnoresRangeIsRefused() async {
            // A 200 would be the whole file — sixty gigabytes for a REMUX.
            let file = EBML.file(tracks: [EBML.Track(type: 17, language: "heb")])
            MockURLProtocol.handler = Self.serve(file, log: RangeLog(), status: 200)
            #expect(await probe().tracks(at: url) == nil)
        }

        @Test func anHTTPErrorIsTransient() async {
            MockURLProtocol.stub(status: 404, json: "")
            #expect(await probe().tracks(at: url) == nil)
        }

        @Test func anMP4IsNotMatroska() async {
            MockURLProtocol.handler = Self.serve(Array("....ftypisom....moov".utf8), log: RangeLog())
            #expect(await probe().tracks(at: url) == .notMatroska)
        }

        @Test func aMatroskaFileWithNoTrackListIsUnreadable() async {
            let file = EBML.header() + EBML.idBytes(MatroskaTrackReader.ID.segment) + EBML.unknownSize
                + EBML.element(MatroskaTrackReader.ID.cluster, [0x81])
            MockURLProtocol.handler = Self.serve(file, log: RangeLog())
            #expect(await probe().tracks(at: url) == .unreadable)
        }
    }
}
