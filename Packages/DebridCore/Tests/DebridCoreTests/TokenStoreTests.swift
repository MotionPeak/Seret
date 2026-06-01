import Testing
import Foundation
@testable import DebridCore

struct TokenStoreTests {
    private func sample() -> StoredCredentials {
        StoredCredentials(
            token: RDToken(accessToken: "AT", refreshToken: "RT", expiresIn: 3600, tokenType: "Bearer"),
            deviceCredentials: RDDeviceCredentials(clientID: "CID", clientSecret: "CSECRET"),
            obtainedAt: Date(timeIntervalSince1970: 1_000_000))
    }

    @Test func savesAndLoads() throws {
        let store = InMemoryTokenStore()
        #expect(try store.load() == nil)
        try store.save(sample())
        #expect(try store.load() == sample())
    }

    @Test func clearsCredentials() throws {
        let store = InMemoryTokenStore()
        try store.save(sample())
        try store.clear()
        #expect(try store.load() == nil)
    }
}
