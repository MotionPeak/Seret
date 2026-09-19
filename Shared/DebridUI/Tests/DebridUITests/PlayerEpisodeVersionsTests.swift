import Testing
import Foundation
@testable import DebridUI
import DebridCore

/// An episode you own more than one copy of must be able to fall back mid-playback.
///
/// The bug this pins: `switchTo` set `sources = [ep.source]` — a single element — so
/// `canTryAnotherVersion` (`sourceIndex + 1 < sources.count`) was ALWAYS false for an episode. A
/// stream that went bad in the middle of a season was a dead end with no recovery, while a movie
/// in the same situation offered every other owned copy.
@MainActor
@Suite struct PlayerEpisodeVersionsTests {

    private static func source(_ id: String) -> MediaSource {
        MediaSource(torrentID: id, fileID: nil, restrictedLink: "rd://\(id)",
                    parsed: ParsedRelease(title: "The Show", season: 1, episode: 1))
    }

    /// A two-episode show where the PLAYING episode owns two copies.
    private static func request(alternates: [MediaSource]) -> PlaybackRequest {
        let ep1 = Episode(season: 1, number: 1, source: source("e1"), alternates: alternates)
        let ep2 = Episode(season: 1, number: 2, source: source("e2"))
        let item = MediaItem(id: "s1", kind: .show, title: "The Show", year: 2023,
                             sources: [], seasons: [Season(number: 1, episodes: [ep1, ep2])],
                             tmdbID: 1399)
        return PlaybackRequest(item: item, source: ep1.source, resumeAt: nil,
                               label: "The Show — S1·E1",
                               contentKey: WatchKey.content(forShow: item, episode: ep1),
                               episode: ep1)
    }

    private func model(_ request: PlaybackRequest) -> PlayerModel {
        PlayerModel(request: request, engine: FakeVideoPlayerEngine(),
                    unrestrict: { _ in URL(string: "https://cdn/x.mkv")! },
                    recordProgress: { _, _, _, _, _ in }, subtitles: nil)
    }

    /// Switching to an episode must carry ALL of its owned copies, not just the primary.
    @Test func switchingEpisodeCarriesEveryOwnedCopy() async {
        let m = model(Self.request(alternates: []))
        m.start()
        await m.waitForIdleForTesting()

        let target = Episode(season: 1, number: 2, source: Self.source("e2"),
                             alternates: [Self.source("e2-alt")])
        m.play(target)
        await m.waitForIdleForTesting()

        #expect(m.canTryAnotherVersion)
    }

    /// The episode the player OPENS with must offer its alternates too — not only ones switched to.
    @Test func theOpeningEpisodeOffersItsAlternates() async {
        let m = model(Self.request(alternates: [Self.source("e1-alt")]))
        m.start()
        await m.waitForIdleForTesting()

        #expect(m.canTryAnotherVersion)
    }

    /// An episode with a single copy still reports no fallback — this must not become always-true.
    @Test func aSingleCopyEpisodeStillOffersNoFallback() async {
        let m = model(Self.request(alternates: []))
        m.start()
        await m.waitForIdleForTesting()

        #expect(!m.canTryAnotherVersion)
    }

    /// Falling back actually moves to the alternate's link rather than reloading the same one.
    @Test func tryingAnotherVersionLoadsTheAlternate() async {
        let engine = FakeVideoPlayerEngine()
        let m = PlayerModel(request: Self.request(alternates: [Self.source("e1-alt")]),
                            engine: engine,
                            unrestrict: { URL(string: "https://cdn/\($0.replacingOccurrences(of: "rd://", with: ""))")! },
                            recordProgress: { _, _, _, _, _ in }, subtitles: nil)
        m.start()
        await m.waitForIdleForTesting()
        #expect(engine.loadedURL?.absoluteString == "https://cdn/e1")

        m.tryAnotherVersion()
        await m.waitForIdleForTesting()
        #expect(engine.loadedURL?.absoluteString == "https://cdn/e1-alt")
    }
}
