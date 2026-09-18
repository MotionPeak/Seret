import Testing
import Foundation
@testable import DebridCore

@Suite struct LetterboxdDiaryFormTests {
    let utc = TimeZone(identifier: "UTC")!

    func write(rating: Int?, watchedAt: Date?, rewatch: Bool = false) -> LetterboxdWrite {
        LetterboxdWrite(tmdbID: 550, rating: rating, watchedAt: watchedAt, rewatch: rewatch)
    }

    @Test func aDateIsTheLocalDay() {
        let instant = Date(timeIntervalSince1970: 1_700_000_000)   // 2023-11-14 22:13:20 UTC
        #expect(LetterboxdDiaryForm.dateString(instant, timeZone: utc) == "2023-11-14")
    }

    /// A watch date is a local-day fact: finishing just after midnight in Tel Aviv is that day
    /// there, even though UTC still calls it yesterday.
    @Test func theDateFollowsTheViewersCalendarNotUTC() {
        let instant = Date(timeIntervalSince1970: 1_700_000_000)
        let il = TimeZone(identifier: "Asia/Jerusalem")!
        #expect(LetterboxdDiaryForm.dateString(instant, timeZone: il) == "2023-11-15")
        #expect(LetterboxdDiaryForm.dateString(instant, timeZone: utc) == "2023-11-14")
    }

    @Test func aDatedEntryAsksToBeInTheDiary() {
        let f = LetterboxdDiaryForm.fields(
            for: write(rating: 8, watchedAt: Date(timeIntervalSince1970: 1_700_000_000)),
            filmUid: "film:1620206", csrf: "TOKEN", timeZone: utc)
        #expect(f["viewingableUid"] == "film:1620206")
        #expect(f["__csrf"] == "TOKEN")
        #expect(f["specifiedDate"] == "true")
        #expect(f["viewingDateStr"] == "2023-11-14")
        #expect(f["rating"] == "8")
    }

    /// Empty means "create a new entry". Seret only ever appends; it must never edit one the
    /// owner made themselves.
    @Test func viewingIdIsAlwaysEmpty() {
        let f = LetterboxdDiaryForm.fields(for: write(rating: nil, watchedAt: Date()),
                                           filmUid: "film:1", csrf: "T")
        #expect(f["viewingId"] == "")
    }

    @Test func rewatchIsSentOnlyWhenTrue() {
        let first = LetterboxdDiaryForm.fields(for: write(rating: nil, watchedAt: Date(), rewatch: false),
                                               filmUid: "film:1", csrf: "T")
        let again = LetterboxdDiaryForm.fields(for: write(rating: nil, watchedAt: Date(), rewatch: true),
                                               filmUid: "film:1", csrf: "T")
        // An unchecked checkbox is absent from a form post, not "false".
        #expect(first["rewatch"] == nil)
        #expect(again["rewatch"] == "true")
    }

    @Test func noRatingSendsNoRatingField() {
        let f = LetterboxdDiaryForm.fields(for: write(rating: nil, watchedAt: Date()),
                                           filmUid: "film:1", csrf: "T")
        #expect(f["rating"] == nil)
    }

    /// Without a date there is nothing to put in a diary, so it is not a diary entry at all.
    @Test func noDateMeansNoSpecifiedDate() {
        let f = LetterboxdDiaryForm.fields(for: write(rating: 7, watchedAt: nil),
                                           filmUid: "film:1", csrf: "T")
        #expect(f["specifiedDate"] == nil)
        #expect(f["viewingDateStr"] == nil)
        #expect(f["rating"] == "7")
    }

    @Test func nothingElseIsEverSent() {
        let f = LetterboxdDiaryForm.fields(for: write(rating: 8, watchedAt: Date(), rewatch: true),
                                           filmUid: "film:1", csrf: "T")
        for unexpected in ["review", "tags", "containsSpoilers", "liked"] {
            #expect(f[unexpected] == nil)
        }
    }
}
