import Testing
@testable import DebridCore

/// Pure suite (no network, no SwiftData) — stays a plain top-level struct.
@Suite struct ReleaseMatcherTests {
    let matcher = ReleaseMatcher()

    // MARK: - Movies

    @Test func acceptsLegitReleaseWithMatchingTitleAndYear() {
        let r = ParsedRelease(title: "Obsession", year: 2026, resolution: "1080p", source: "WEB-DL")
        #expect(matcher.matchesMovie(r, title: "Obsession", year: 2026))
    }

    @Test func acceptsCamForTheCorrectNewFilm() {
        // A genuinely-new film's only cached release may be a CAM with no resolution/source.
        // It still matches by title + year and should pass.
        let r = ParsedRelease(title: "Obsession", year: 2026)
        #expect(matcher.matchesMovie(r, title: "Obsession", year: 2026))
    }

    @Test func rejectsSameTitleWrongYear() {
        // The 1991 erotic film named "Obsession" must NOT pass as a version of the 2026 film.
        let r = ParsedRelease(title: "Obsession", year: 1991, source: "DVDRip")
        #expect(!matcher.matchesMovie(r, title: "Obsession", year: 2026))
    }

    @Test func rejectsBareYearlessNoQualityJunk() {
        // "Obsession.avi" — no year, no quality metadata. Exactly the junk that renders a blank
        // version row and plays the wrong film.
        let r = ParsedRelease(title: "Obsession")
        #expect(!matcher.matchesMovie(r, title: "Obsession", year: 2026))
    }

    @Test func acceptsYearlessReleaseThatCarriesQuality() {
        let r = ParsedRelease(title: "Obsession", resolution: "1080p")
        #expect(matcher.matchesMovie(r, title: "Obsession", year: 2026))
    }

    @Test func rejectsDifferentFilmEvenWithMatchingYear() {
        let r = ParsedRelease(title: "Tenet", year: 2026, resolution: "1080p")
        #expect(!matcher.matchesMovie(r, title: "Obsession", year: 2026))
    }

    @Test func acceptsWithinOneYearTolerance() {
        // An early cam can be tagged the year before release.
        let r = ParsedRelease(title: "Obsession", year: 2025, resolution: "720p")
        #expect(matcher.matchesMovie(r, title: "Obsession", year: 2026))
    }

    @Test func acceptsTitleWithExtraLeadingTokens() {
        let r = ParsedRelease(title: "The Obsession", year: 2026, resolution: "1080p")
        #expect(matcher.matchesMovie(r, title: "Obsession", year: 2026))
    }

    @Test func normalizesPunctuationAndSeparators() {
        let r = ParsedRelease(title: "Spider Man No Way Home", year: 2021, resolution: "2160p")
        #expect(matcher.matchesMovie(r, title: "Spider-Man: No Way Home", year: 2021))
    }

    @Test func emptyRequestedTitleDoesNotFilter() {
        let r = ParsedRelease(title: "Anything", year: 1999)
        #expect(matcher.matchesMovie(r, title: "", year: 2026))
    }

    // MARK: - Series (title-only; per-episode years are unreliable, so no year gate)

    @Test func acceptsEpisodeOfTheRequestedShow() {
        let r = ParsedRelease(title: "The Office", season: 5, episode: 3, resolution: "1080p")
        #expect(matcher.matchesSeries(r, title: "The Office"))
    }

    @Test func rejectsEpisodeOfTheWrongShow() {
        let r = ParsedRelease(title: "Friends", season: 1, episode: 1, resolution: "1080p")
        #expect(!matcher.matchesSeries(r, title: "The Office"))
    }

    @Test func seriesIgnoresYearMismatch() {
        // Show first aired 2015; an S05 episode tagged 2020 must still match.
        let r = ParsedRelease(title: "The Office", year: 2020, season: 5, episode: 3)
        #expect(matcher.matchesSeries(r, title: "The Office"))
    }
}
