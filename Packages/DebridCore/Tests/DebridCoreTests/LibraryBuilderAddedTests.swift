import Testing
import Foundation
@testable import DebridCore

@Suite struct LibraryBuilderAddedTests {
    @Test func parsesISO8601WithFractionalSeconds() {
        #expect(LibraryBuilder.parseAdded("2026-06-01T10:30:00.000Z") != nil)
    }

    @Test func parsesISO8601WithoutFractionalSeconds() {
        #expect(LibraryBuilder.parseAdded("2026-06-01T10:30:00Z") != nil)
    }

    @Test func returnsNilForGarbage() {
        #expect(LibraryBuilder.parseAdded("not-a-date") == nil)
        #expect(LibraryBuilder.parseAdded(nil) == nil)
    }
}
