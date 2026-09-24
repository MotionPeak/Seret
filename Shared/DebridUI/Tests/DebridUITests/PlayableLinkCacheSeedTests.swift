import Testing
import Foundation
@testable import DebridUI

@Suite struct PlayableLinkCacheSeedTests {
    final class Resolves: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        func hit() { lock.lock(); count += 1; lock.unlock() }
        var value: Int { lock.lock(); defer { lock.unlock() }; return count }
    }

    final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var current = Date(timeIntervalSince1970: 0)
        var now: Date { lock.lock(); defer { lock.unlock() }; return current }
        func advance(_ s: TimeInterval) { lock.lock(); current += s; lock.unlock() }
    }

    @Test func aSeededLinkIsServedWithoutAnotherUnrestrict() async throws {
        let resolves = Resolves()
        let cache = PlayableLinkCache { _ in resolves.hit(); return URL(string: "https://fresh")! }
        await cache.seed("rd://a", url: URL(string: "https://seeded")!)
        #expect(try await cache.consume("rd://a").absoluteString == "https://seeded")
        #expect(resolves.value == 0)
    }

    @Test func aSeedNeverDisplacesAResolveInFlight() async throws {
        let cache = PlayableLinkCache { _ in URL(string: "https://fresh")! }
        await cache.prefetch("rd://a")
        await cache.seed("rd://a", url: URL(string: "https://seeded")!)
        #expect(try await cache.consume("rd://a").absoluteString == "https://fresh")
    }

    @Test func aSeedExpiresLikeAnyEntry() async throws {
        let clock = Clock()
        let cache = PlayableLinkCache(ttl: 60, now: { clock.now }) { _ in URL(string: "https://fresh")! }
        await cache.seed("rd://a", url: URL(string: "https://seeded")!)
        clock.advance(61)
        #expect(try await cache.consume("rd://a").absoluteString == "https://fresh")
    }
}
