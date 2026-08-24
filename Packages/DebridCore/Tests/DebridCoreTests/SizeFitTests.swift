import Testing
@testable import DebridCore

/// How well a file's size fits what its resolution and shape should reasonably weigh.
///
/// Ranking used to treat "bigger" as "better" outright, so the default pick for a 4K title was
/// the largest untranscoded Blu-ray on offer — 70–80 GB. Those open slowly, skip roughly, and
/// press hard on an Apple TV's memory. This scores the sweet spot instead.
struct SizeFitTests {
    private func gb(_ n: Double) -> Int { Int(n * 1_000_000_000) }

    // MARK: - Movies

    @Test func aRightSizedMovieIsIdeal() {
        #expect(sizeFit(bytes: gb(25), resolution: "2160p", shape: .movie) == .ideal)
        #expect(sizeFit(bytes: gb(12), resolution: "2160p", shape: .movie) == .ideal)
        #expect(sizeFit(bytes: gb(35), resolution: "2160p", shape: .movie) == .ideal)
    }

    /// The reported complaint: 70–80 GB releases. They must land in the worst bucket so anything
    /// reasonable outranks them.
    @Test func aBloatedMovieIsFar() {
        #expect(sizeFit(bytes: gb(70), resolution: "2160p", shape: .movie) == .far)
        #expect(sizeFit(bytes: gb(80), resolution: "2160p", shape: .movie) == .far)
    }

    /// Just outside the band is `near`, not `far` — a 45 GB 4K release is heavy but not absurd,
    /// and must still beat an 80 GB one.
    @Test func slightlyOversizeIsNear() {
        #expect(sizeFit(bytes: gb(45), resolution: "2160p", shape: .movie) == .near)
        #expect(sizeFit(bytes: gb(8), resolution: "2160p", shape: .movie) == .near)
    }

    /// A "4K" file far too small to be one is suspect and ranks with the bloat.
    @Test func anImplausiblySmallFileIsFar() {
        #expect(sizeFit(bytes: gb(1), resolution: "2160p", shape: .movie) == .far)
    }

    @Test func bandsScaleDownWithResolution() {
        #expect(sizeFit(bytes: gb(10), resolution: "1080p", shape: .movie) == .ideal)
        #expect(sizeFit(bytes: gb(10), resolution: "720p", shape: .movie) == .near)
        #expect(sizeFit(bytes: gb(4), resolution: "720p", shape: .movie) == .ideal)
    }

    // MARK: - Episodes

    /// An episode is a fraction of a film's runtime, so the same byte count means something
    /// different. 25 GB is an ideal FILM and an absurd episode.
    @Test func episodeBandsAreMuchSmallerThanMovieBands() {
        #expect(sizeFit(bytes: gb(25), resolution: "2160p", shape: .episode) == .far)
        #expect(sizeFit(bytes: gb(5), resolution: "2160p", shape: .episode) == .ideal)
        #expect(sizeFit(bytes: gb(2), resolution: "1080p", shape: .episode) == .ideal)
    }

    // MARK: - Season packs

    /// A pack is big by definition. Without an episode count there is nothing to compare against,
    /// so it must NOT be penalised — otherwise every season pack in existence ranks last.
    @Test func aSeasonPackWithNoEpisodeCountIsNeverPenalised() {
        #expect(sizeFit(bytes: gb(300), resolution: "2160p", shape: .seasonPack(episodes: nil)) == .ideal)
    }

    /// With a count, the pack is judged per episode — 10 × 5 GB is a sensible 4K season.
    @Test func aSeasonPackWithACountIsJudgedPerEpisode() {
        #expect(sizeFit(bytes: gb(50), resolution: "2160p", shape: .seasonPack(episodes: 10)) == .ideal)
        #expect(sizeFit(bytes: gb(300), resolution: "2160p", shape: .seasonPack(episodes: 10)) == .far)
    }

    @Test func aZeroEpisodeCountDoesNotDivideByZero() {
        #expect(sizeFit(bytes: gb(50), resolution: "2160p", shape: .seasonPack(episodes: 0)) == .ideal)
    }

    // MARK: - Unknowns

    /// Unknown size is neutral: it must not beat a known-good file, nor lose to known bloat.
    @Test func unknownSizeIsNeutral() {
        #expect(sizeFit(bytes: nil, resolution: "2160p", shape: .movie) == .near)
        #expect(sizeFit(bytes: gb(25), resolution: "2160p", shape: .movie) > .near)
        #expect(sizeFit(bytes: gb(80), resolution: "2160p", shape: .movie) < .near)
    }

    @Test func unknownResolutionUsesAWideBand() {
        #expect(sizeFit(bytes: gb(10), resolution: nil, shape: .movie) == .ideal)
        #expect(sizeFit(bytes: gb(80), resolution: nil, shape: .movie) == .far)
    }

    // MARK: - Shape derivation

    @Test func shapeIsDerivedFromTheParsedRelease() {
        #expect(ReleaseShape.of(ParsedRelease(title: "x")) == .movie)
        #expect(ReleaseShape.of(ParsedRelease(title: "x", season: 1, episode: 3)) == .episode)
        #expect(ReleaseShape.of(ParsedRelease(title: "x", season: 1)) == .seasonPack(episodes: nil))
        #expect(ReleaseShape.of(ParsedRelease(title: "x", season: 1), episodes: 8)
                == .seasonPack(episodes: 8))
    }
}
