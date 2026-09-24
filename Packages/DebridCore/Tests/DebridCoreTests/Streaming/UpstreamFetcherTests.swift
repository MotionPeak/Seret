import Foundation
import Testing
@testable import DebridCore

extension StreamingNetworkTests {
    @Suite struct UpstreamFetcherTests {
        init() { RangeFileURLProtocol.reset(.init(fileSize: 3 << 20)) }

        private func collect(_ fetcher: UpstreamFetcher) async -> (status: Int?, total: Int64?, body: Data, error: StreamError?) {
            var status: Int?, total: Int64?, body = Data(), failure: StreamError?
            for await event in fetcher.events {
                switch event {
                case .response(let s, let t, _): status = s; total = t
                case .data(let d): body.append(d)
                case .finished(let e): failure = e
                }
            }
            return (status, total, body, failure)
        }

        @Test func streamsTheRequestedRangeInOrder() async {
            let fetcher = UpstreamFetcher(url: URL(string: "https://rd.test/f.mkv")!, start: 1 << 20,
                                          configuration: RangeFileURLProtocol.configuration)
            fetcher.start()
            let result = await collect(fetcher)
            #expect(result.status == 206)
            #expect(result.total == 3 << 20)
            #expect(result.body == RangeFileURLProtocol.bytes((1 << 20)..<(3 << 20)))
            #expect(result.error == nil)
            #expect(RangeFileURLProtocol.requests.map(\.start) == [1 << 20])
        }

        @Test func aRefusalIsReportedWithItsStatus() async {
            RangeFileURLProtocol.reset(.init(statusByPath: ["/gone.mkv": 404]))
            let fetcher = UpstreamFetcher(url: URL(string: "https://rd.test/gone.mkv")!, start: 0,
                                          configuration: RangeFileURLProtocol.configuration)
            fetcher.start()
            let result = await collect(fetcher)
            #expect(result.status == 404)
            #expect(result.body.isEmpty)
        }

        @Test func cancellingEndsTheEventStream() async {
            RangeFileURLProtocol.reset(.init(fileSize: 64 << 20))
            let fetcher = UpstreamFetcher(url: URL(string: "https://rd.test/f.mkv")!, start: 0,
                                          configuration: RangeFileURLProtocol.configuration)
            fetcher.start()
            var received = 0
            for await event in fetcher.events {
                if case .data(let d) = event {
                    received += d.count
                    if received > 1 << 20 { fetcher.cancel() }
                }
            }
            #expect(received < 64 << 20)              // it stopped long before the end
        }

        @Test func theTotalComesFromContentRange() {
            let r = HTTPURLResponse(url: URL(string: "https://rd.test/x")!, statusCode: 206,
                                    httpVersion: nil,
                                    headerFields: ["Content-Range": "bytes 5-9/72733242317"])!
            #expect(UpstreamFetcher.totalSize(from: r) == 72_733_242_317)
        }
    }
}
