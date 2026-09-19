import Testing
import Foundation
@testable import DebridCore

@Suite struct LetterboxdLogEntryTests {
    let utc = TimeZone(identifier: "UTC")!

    func write(rating: Int?, watchedAt: Date?, rewatch: Bool = false) -> LetterboxdWrite {
        LetterboxdWrite(tmdbID: 550, rating: rating, watchedAt: watchedAt, rewatch: rewatch)
    }

    func payload(_ write: LetterboxdWrite, _ zone: TimeZone? = nil) throws -> [String: Any] {
        let json = try LetterboxdLogEntry.json(for: write, timeZone: zone ?? utc)
        return try #require((try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any])
    }

    @Test func aDateIsTheLocalDay() {
        let instant = Date(timeIntervalSince1970: 1_700_000_000)   // 2023-11-14 22:13:20 UTC
        #expect(LetterboxdLogEntry.dateString(instant, timeZone: utc) == "2023-11-14")
    }

    /// A watch date is a local-day fact: finishing just after midnight in Tel Aviv is that day
    /// there, even though UTC still calls it yesterday.
    @Test func theDateFollowsTheViewersCalendarNotUTC() {
        let instant = Date(timeIntervalSince1970: 1_700_000_000)
        let il = TimeZone(identifier: "Asia/Jerusalem")!
        #expect(LetterboxdLogEntry.dateString(instant, timeZone: il) == "2023-11-15")
        #expect(LetterboxdLogEntry.dateString(instant, timeZone: utc) == "2023-11-14")
    }

    /// 🚨 The API takes a rating out of FIVE, not out of ten - their own response handler doubles
    /// it coming back. Sending 8 would be a request for four stars beyond the top of the scale.
    @Test func theRatingIsHalvedForTheApiScale() throws {
        #expect(try payload(write(rating: 8, watchedAt: nil))["rating"] as? Double == 4)
        #expect(try payload(write(rating: 7, watchedAt: nil))["rating"] as? Double == 3.5)
        #expect(try payload(write(rating: 10, watchedAt: nil))["rating"] as? Double == 5)
    }

    @Test func anUnratedWriteCarriesNoRating() throws {
        #expect(try payload(write(rating: nil, watchedAt: nil))["rating"] == nil)
    }

    @Test func aWatchDateBecomesDiaryDetails() throws {
        let body = try payload(write(rating: 8, watchedAt: Date(timeIntervalSince1970: 1_700_000_000),
                                     rewatch: true))
        let details = try #require(body["diaryDetails"] as? [String: Any])
        #expect(details["diaryDate"] as? String == "2023-11-14")
        #expect(details["rewatch"] as? Bool == true)
    }

    /// Without a date there is no diary entry to describe, and their own builder omits the key
    /// rather than sending an empty object.
    @Test func noWatchDateMeansNoDiaryDetailsAtAll() throws {
        #expect(try payload(write(rating: 8, watchedAt: nil))["diaryDetails"] == nil)
    }

    /// `productionId` is deliberately absent: only the loaded page knows the film's uid, so it is
    /// merged in there. Putting a guess here would write a rating onto the wrong film.
    @Test func theProductionIsNamedByThePageNotHere() throws {
        #expect(try payload(write(rating: 8, watchedAt: nil))["productionId"] == nil)
    }
}
