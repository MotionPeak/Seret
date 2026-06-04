import Testing
import Foundation
@testable import DebridCore

@Suite struct SecretStoreTests {
    @Test func inMemoryRoundTripsAndClears() throws {
        let store: SecretStore = InMemorySecretStore()
        #expect(try store.read() == nil)

        let payload = Data("hello".utf8)
        try store.write(payload)
        #expect(try store.read() == payload)

        try store.clear()
        #expect(try store.read() == nil)
    }

    @Test func writeOverwritesPreviousValue() throws {
        let store: SecretStore = InMemorySecretStore()
        try store.write(Data("one".utf8))
        try store.write(Data("two".utf8))
        #expect(try store.read() == Data("two".utf8))
    }
}
