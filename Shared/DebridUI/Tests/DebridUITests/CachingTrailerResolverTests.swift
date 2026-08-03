import Testing
import Foundation
@testable import DebridUI

/// Every trailer resolution YouTubeKit performs locally evaluates YouTube's player JS in
/// JavaScriptCore, and JSC **aborts the process** when its heap is exhausted
/// (`JSC::handleResourceExhaustion` — there is no error to catch, it just dies). That crash is in
/// this app's reports. Since the evaluation itself can't be made safe, the lever is to run it as
/// few times as possible: never twice for the same video, and never twice concurrently.
@Suite struct CachingTrailerResolverTests {

    /// Counts calls and can be held open, so concurrency is observable rather than raced.
    private actor CountingResolver: TrailerStreamResolving {
        private(set) var calls = 0
        private let url: URL?
        private var gate: CheckedContinuation<Void, Never>?
        private var held: Bool

        init(url: URL?, held: Bool = false) {
            self.url = url
            self.held = held
        }

        func streamURL(youTubeKey: String) async -> URL? {
            calls += 1
            if held {
                await withCheckedContinuation { gate = $0 }
            }
            return url
        }

        func release() {
            held = false
            gate?.resume()
            gate = nil
        }
        func callCount() -> Int { calls }
    }

    private let url = URL(string: "https://v/1.mp4")!

    @Test func aRepeatLookupIsServedFromCache() async {
        let base = CountingResolver(url: url)
        let resolver = CachingTrailerStreamResolver(base: base)

        let first = await resolver.streamURL(youTubeKey: "abc")
        let second = await resolver.streamURL(youTubeKey: "abc")

        #expect(first == url)
        #expect(second == url)
        #expect(await base.callCount() == 1)   // the JS ran once, not twice
    }

    @Test func differentVideosEachResolve() async {
        let base = CountingResolver(url: url)
        let resolver = CachingTrailerStreamResolver(base: base)

        _ = await resolver.streamURL(youTubeKey: "abc")
        _ = await resolver.streamURL(youTubeKey: "def")

        #expect(await base.callCount() == 2)
    }

    /// A failed extraction is remembered too. Otherwise pressing Trailer on a title that cannot be
    /// extracted would re-run the JS on every press — the worst case for a crash that is triggered
    /// by running it at all.
    @Test func aFailureIsCachedSoItIsNotRetriedForever() async {
        let base = CountingResolver(url: nil)
        let resolver = CachingTrailerStreamResolver(base: base)

        let first = await resolver.streamURL(youTubeKey: "abc")
        let second = await resolver.streamURL(youTubeKey: "abc")

        #expect(first == nil)
        #expect(second == nil)
        #expect(await base.callCount() == 1)
    }

    /// Two screens asking at the same moment must share ONE evaluation — two concurrent JSContexts
    /// each holding YouTube's multi-megabyte player script is exactly the memory spike to avoid.
    @Test func concurrentLookupsForTheSameVideoCoalesce() async {
        let base = CountingResolver(url: url, held: true)
        let resolver = CachingTrailerStreamResolver(base: base)

        async let a = resolver.streamURL(youTubeKey: "abc")
        async let b = resolver.streamURL(youTubeKey: "abc")
        // Let both callers reach the resolver before the single underlying call completes.
        while await base.callCount() == 0 { await Task.yield() }
        await base.release()

        let results = await [a, b]
        #expect(results == [url, url])
        #expect(await base.callCount() == 1)
    }
}
