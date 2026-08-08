import Testing
import Foundation
import DebridCore
@testable import DebridUI

private func credit(_ id: Int, _ title: String, popularity: Double,
                    character: String? = nil, job: String? = nil,
                    kind: MediaKind = .movie) -> TMDBPersonCredit {
    TMDBPersonCredit(
        result: TMDBSearchResult(id: id, title: title, name: nil, releaseDate: "2020-01-01",
                                 firstAirDate: nil, posterPath: "/p.jpg", overview: nil,
                                 voteAverage: nil),
        kind: kind, character: character, job: job, popularity: popularity)
}

/// The store behind the person page: it loads once, ranks through the DebridCore helpers, and
/// hands the UI `SearchHit`s so a credit routes exactly like a search result.
@MainActor
@Suite struct PersonStoreTests {
    private let ref = TMDBPersonRef(id: 1234, name: "Denis Villeneuve")

    struct Fake: PersonCreditsProviding {
        var details = TMDBPersonDetails(
            id: 1234, name: "Denis Villeneuve", profilePath: "/dv.jpg",
            knownForDepartment: "Directing",
            castCredits: [credit(1, "Talk Show", popularity: 99, character: "Self"),
                          credit(2, "Cameo", popularity: 5, character: "Man in Bar")],
            crewCredits: [credit(3, "Arrival", popularity: 80, job: "Director"),
                          credit(4, "Produced Thing", popularity: 95, job: "Producer")])
        var error: (any Error)?
        func person(tmdbID: Int) async throws -> TMDBPersonDetails {
            if let error { throw error }
            return details
        }
    }

    struct Boom: Error {}

    @Test func loadsRanksAndSplitsByRole() async {
        let store = PersonStore(ref: ref, credits: Fake())
        await store.load()

        #expect(store.state == .loaded)
        #expect(store.name == "Denis Villeneuve")
        #expect(store.profilePath == "/dv.jpg")
        // "Talk Show" is a Self credit and is gone; "Produced Thing" is not a directing credit.
        #expect(store.acting.map(\.result.displayTitle) == ["Cameo"])
        #expect(store.directing.map(\.result.displayTitle) == ["Arrival"])
    }

    @Test func handsTheUISearchHitsCarryingTheRightKind() async {
        var fake = Fake()
        fake.details = TMDBPersonDetails(
            id: 1234, name: "P",
            castCredits: [credit(9, "A Series", popularity: 1, character: "Role", kind: .show)])
        let store = PersonStore(ref: ref, credits: fake)
        await store.load()

        #expect(store.acting.first?.kind == .show)
        #expect(store.acting.first?.result.id == 9)
    }

    @Test func showsTheRefNameBeforeAnythingHasLoaded() {
        let store = PersonStore(ref: ref, credits: Fake())
        #expect(store.state == .idle)
        #expect(store.name == "Denis Villeneuve")
    }

    @Test func aPersonWithNothingLeftAfterFilteringIsEmptyNotLoaded() async {
        var fake = Fake()
        fake.details = TMDBPersonDetails(
            id: 1234, name: "P",
            castCredits: [credit(1, "Talk Show", popularity: 99, character: "Self")])
        let store = PersonStore(ref: ref, credits: fake)
        await store.load()

        #expect(store.state == .empty)
        #expect(store.acting.isEmpty)
    }

    @Test func reportsFailure() async {
        var fake = Fake()
        fake.error = Boom()
        let store = PersonStore(ref: ref, credits: fake)
        await store.load()

        #expect(store.state == .failed("Couldn't load Denis Villeneuve."))
    }

    @Test func loadingTwiceDoesNotRefetch() async {
        final class Counting: PersonCreditsProviding, @unchecked Sendable {
            var calls = 0
            func person(tmdbID: Int) async throws -> TMDBPersonDetails {
                calls += 1
                return TMDBPersonDetails(id: tmdbID, name: "P",
                                         castCredits: [credit(1, "Film", popularity: 1,
                                                              character: "Role")])
            }
        }
        let counting = Counting()
        let store = PersonStore(ref: ref, credits: counting)
        await store.load()
        await store.load()
        #expect(counting.calls == 1)
    }
}
