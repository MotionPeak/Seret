import Testing
@testable import DebridCore

@Suite struct LetterboxdImportPlannerTests {
    typealias P = LetterboxdImportPlanner

    @Test func fillsInARatingSeretDoesNotHave() {
        let plan = P.plan(
            candidates: [P.Candidate(contentKey: "movie:tmdb:1637", slug: "speed", existingRating: nil)],
            letterboxdRatings: ["speed": 6])
        #expect(plan.writes == [P.Write(contentKey: "movie:tmdb:1637", rating: 6)])
        #expect(plan.conflicts.isEmpty)
    }

    @Test func neverOverwritesARatingSeretAlreadyHas() {
        let plan = P.plan(
            candidates: [P.Candidate(contentKey: "movie:tmdb:1637", slug: "speed", existingRating: 9)],
            letterboxdRatings: ["speed": 6])
        #expect(plan.writes.isEmpty)
        #expect(plan.conflicts == [P.Conflict(contentKey: "movie:tmdb:1637", local: 9, letterboxd: 6)])
    }

    @Test func anAgreeingRatingIsNeitherAWriteNorAConflict() {
        let plan = P.plan(
            candidates: [P.Candidate(contentKey: "movie:tmdb:1637", slug: "speed", existingRating: 6)],
            letterboxdRatings: ["speed": 6])
        #expect(plan.writes.isEmpty)
        #expect(plan.conflicts.isEmpty)
    }

    @Test func anUnresolvedFilmIsSkipped() {
        let plan = P.plan(
            candidates: [P.Candidate(contentKey: "movie:tmdb:1637", slug: nil, existingRating: nil)],
            letterboxdRatings: ["speed": 6])
        #expect(plan.writes.isEmpty)
    }

    @Test func aFilmLetterboxdHasNotRatedIsSkipped() {
        let plan = P.plan(
            candidates: [P.Candidate(contentKey: "movie:tmdb:99", slug: "watched-but-unrated", existingRating: nil)],
            letterboxdRatings: ["speed": 6])
        #expect(plan.writes.isEmpty)
    }

    @Test func anOutOfRangeRatingIsRefusedRatherThanWritten() {
        let plan = P.plan(
            candidates: [P.Candidate(contentKey: "movie:tmdb:1637", slug: "speed", existingRating: nil)],
            letterboxdRatings: ["speed": 47])
        #expect(plan.writes.isEmpty)
    }

    @Test func aMixedBatchIsSortedOutCorrectly() {
        let plan = P.plan(candidates: [
            P.Candidate(contentKey: "movie:tmdb:1", slug: "a", existingRating: nil),   // write
            P.Candidate(contentKey: "movie:tmdb:2", slug: "b", existingRating: 4),     // conflict
            P.Candidate(contentKey: "movie:tmdb:3", slug: "c", existingRating: nil),   // no LB rating
            P.Candidate(contentKey: "movie:tmdb:4", slug: nil, existingRating: nil)    // unresolved
        ], letterboxdRatings: ["a": 8, "b": 7])
        #expect(plan.writes == [P.Write(contentKey: "movie:tmdb:1", rating: 8)])
        #expect(plan.conflicts == [P.Conflict(contentKey: "movie:tmdb:2", local: 4, letterboxd: 7)])
    }
}
