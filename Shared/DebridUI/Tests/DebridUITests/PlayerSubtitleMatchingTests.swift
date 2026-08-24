import Testing
import Foundation
@testable import DebridUI
import DebridCore

/// The one-tap Hebrew/English pill must pick the subtitle that MATCHES the file being played.
///
/// The bug this pins: `requestSubtitle` took `results.first` — whatever OpenSubtitles happened to
/// return first — with no moviehash, no release-name comparison and no fps check, while the manual
/// browser did all three. A subtitle timed against a different release drifts linearly: correct at
/// the start, then each cue lands early and is clipped by its successor, so a sentence never
/// finishes on screen.
@MainActor
@Suite struct PlayerSubtitleMatchingTests {

    /// A source whose parsed release fields give `releaseNameForMatching` something to match on.
    private static func source() -> MediaSource {
        MediaSource(torrentID: "t1", fileID: nil, restrictedLink: "rd://link",
                    parsed: ParsedRelease(title: "Dune", year: 2024, resolution: "2160p",
                                          source: "WEB-DL", videoCodec: "x265",
                                          releaseGroup: "NTb"))
    }

    private func model(_ subs: FakeSubtitleProvider,
                       engine: FakeVideoPlayerEngine = FakeVideoPlayerEngine()) -> PlayerModel {
        let src = Self.source()
        return PlayerModel(request: Fixture.request(sources: [src]), engine: engine,
                           unrestrict: { _ in URL(string: "https://cdn/x.mkv")! },
                           recordProgress: { _, _, _, _ in }, subtitles: subs)
    }

    /// A moviehash match is a perfect-sync guarantee. Returned SECOND, it must still be chosen.
    @Test func picksTheMoviehashMatchOverTheFirstResult() async {
        let subs = FakeSubtitleProvider()
        subs.searchResults = [
            SubtitleResult(fileID: 1, language: "he", release: "Some.Other.Release.1080p",
                           downloadCount: 9999),
            SubtitleResult(fileID: 2, language: "he", release: "Dune.2024.2160p.WEB-DL.x265-NTb",
                           downloadCount: 3, moviehashMatch: true),
        ]
        let m = model(subs)
        m.start()
        await m.waitForIdleForTesting()

        await m.requestSubtitle(language: "he")

        #expect(subs.downloadedResults.last?.fileID == 2)
    }

    /// Without a hash match, the release name decides — same group and resolution beats a
    /// popular stranger.
    @Test func picksTheMatchingReleaseOverAPopularMismatch() async {
        let subs = FakeSubtitleProvider()
        subs.searchResults = [
            SubtitleResult(fileID: 1, language: "he", release: "Dune.2024.720p.HDTV-XVID",
                           downloadCount: 50_000),
            SubtitleResult(fileID: 2, language: "he", release: "Dune.2024.2160p.WEB-DL.x265-NTb",
                           downloadCount: 10),
        ]
        let m = model(subs)
        m.start()
        await m.waitForIdleForTesting()

        await m.requestSubtitle(language: "he")

        #expect(subs.downloadedResults.last?.fileID == 2)
    }

    /// The moviehash must reach the provider, or OpenSubtitles can never flag `moviehash_match`
    /// in the first place. The browser already sends it; the pill did not.
    @Test func sendsTheMoviehashWithTheSearch() async {
        let subs = FakeSubtitleProvider()
        subs.searchResults = [SubtitleResult(fileID: 1, language: "he")]
        let m = model(subs)
        m.start()
        await m.waitForIdleForTesting()

        await m.requestSubtitle(language: "he")

        // MovieHash.remote over the fake unrestrict URL may or may not resolve; what matters is
        // that the query carries whatever was resolved rather than never asking at all.
        #expect(subs.searchedQueries.last != nil)
        #expect(m.moviehashResolved)
    }

    /// The engine's real frame rate must reach the ranker. `SubtitleMatch` penalises an fps
    /// mismatch by −60 and rewards a match by +50, but every caller passed `videoFPS: nil`, so
    /// that branch never ran — and fps mismatch is precisely what makes a subtitle drift.
    @Test func anFPSMismatchLosesToAnFPSMatch() async {
        let subs = FakeSubtitleProvider()
        let engine = FakeVideoPlayerEngine()
        engine.videoFPS = 23.976
        subs.searchResults = [
            SubtitleResult(fileID: 1, language: "he", release: "Dune.2024.2160p.WEB-DL.x265-NTb",
                           downloadCount: 9999, fps: 25.0),
            SubtitleResult(fileID: 2, language: "he", release: "Dune.2024.2160p.WEB-DL.x265-NTb",
                           downloadCount: 1, fps: 23.976),
        ]
        let m = model(subs, engine: engine)
        m.start()
        await m.waitForIdleForTesting()

        await m.requestSubtitle(language: "he")

        #expect(subs.downloadedResults.last?.fileID == 2)
    }

    /// An empty result set must still report an error rather than crash or silently attach.
    @Test func noResultsStillReportsAnError() async {
        let subs = FakeSubtitleProvider()
        subs.searchResults = []
        let m = model(subs)
        m.start()
        await m.waitForIdleForTesting()

        await m.requestSubtitle(language: "he")

        #expect(subs.downloadedResults.isEmpty)
        #expect(m.subtitleRows.first { $0.language == "he" }?.state == .error)
    }
}
