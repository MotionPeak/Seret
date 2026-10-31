import Testing
@testable import DebridCore

@Suite struct DebridRateLimitTests {
    @Test func recognisesEveryProvidersLimit() {
        #expect(DebridRateLimit.matches(RDAddError.rateLimited))
        #expect(DebridRateLimit.matches(TorBoxError.rateLimited(retryAfter: 300)))
        #expect(DebridRateLimit.matches(HTTPError.status(code: 429, body: "")))
    }

    @Test func otherFailuresAreNotTheLimit() {
        #expect(!DebridRateLimit.matches(RDAddError.notInstant(torrentID: "T")))
        #expect(!DebridRateLimit.matches(RDAddError.blocked))
        #expect(!DebridRateLimit.matches(HTTPError.status(code: 503, body: "")))
        #expect(!DebridRateLimit.matches(TorBoxError.notSignedIn))
    }
}
