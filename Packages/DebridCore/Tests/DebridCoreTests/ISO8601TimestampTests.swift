import Foundation
import Testing
@testable import DebridCore

/// Characterizes the one shared parser that replaced three hand-rolled copies (Trakt's
/// `watched_at`/`paused_at`/`last_watched_at`, RD's `added`). The shapes below are the ones
/// those upstreams actually send.
@Suite struct ISO8601TimestampTests {
    private func date(_ iso: String) -> Date? { ISO8601Timestamp.date(from: iso) }

    @Test func parsesFractionalSeconds() throws {
        let d = try #require(date("2026-07-24T10:00:00.000Z"))
        #expect(d == Date(timeIntervalSince1970: 1_784_887_200))
    }

    /// The shape that used to fail: same instant, no fractional part.
    @Test func parsesPlainSeconds() throws {
        let d = try #require(date("2026-07-24T10:00:00Z"))
        #expect(d == Date(timeIntervalSince1970: 1_784_887_200))
    }

    /// Both shapes must resolve to the SAME instant, or sorting a mixed list silently reorders it.
    @Test func bothShapesAgreeOnTheInstant() throws {
        #expect(try #require(date("2026-07-24T10:00:00.000Z"))
                == (try #require(date("2026-07-24T10:00:00Z"))))
    }

    @Test func parsesANonUTCOffset() throws {
        // 13:00+03:00 is the same instant as 10:00Z.
        #expect(try #require(date("2026-07-24T13:00:00+03:00"))
                == (try #require(date("2026-07-24T10:00:00Z"))))
    }

    @Test func nilAndGarbageYieldNil() {
        #expect(date(from: nil) == nil)
        #expect(date("") == nil)
        #expect(date("not a date") == nil)
        #expect(date("2026-07-24") == nil)          // date-only: not a timestamp we accept
    }

    private func date(from string: String?) -> Date? { ISO8601Timestamp.date(from: string) }
}
