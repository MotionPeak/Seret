import Testing
import Foundation
@testable import DebridCore

@Suite struct OpenSubtitlesResetTimeTests {
    @Test func parsesISO8601UTC() throws {
        let date = try #require(OpenSubtitlesProvider.parseResetTime("2026-06-03T00:00:00Z"))
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        #expect(c.year == 2026 && c.month == 6 && c.day == 3)
        #expect(c.hour == 0 && c.minute == 0 && c.second == 0)
    }

    @Test func nilForUnparseableOrNil() {
        #expect(OpenSubtitlesProvider.parseResetTime("not a date") == nil)
        #expect(OpenSubtitlesProvider.parseResetTime(nil) == nil)
    }
}
