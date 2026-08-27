import Testing
import Foundation
@testable import DebridUI
import DebridCore

/// A subtitle authored against a different frame rate must be corrected before it is attached.
///
/// The bug this pins is the one that makes a title unwatchable partway through: every subtitle
/// OpenSubtitles carries for a BBC show is timed against the 25fps PAL master, and a 23.976 encode
/// runs ~4% longer. Ranking cannot help — there is no correctly-timed candidate to rank — so the
/// chosen file has to be rescaled, or each cue lands progressively early until it is clipped by
/// its successor and no sentence finishes on screen.
@MainActor
@Suite struct PlayerSubtitleRetimeTests {

    /// An hour into the file — far enough in that a 4% error is two and a half minutes.
    private static let srt = """
    1
    01:00:00,000 --> 01:00:02,000
    Line one.
    """

    private func writeSubtitle(_ text: String = srt) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("retime-test-\(UUID().uuidString).srt")
        try! text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func model(_ subs: FakeSubtitleProvider,
                       engine: FakeVideoPlayerEngine) -> PlayerModel {
        let src = MediaSource(torrentID: "t1", fileID: nil, restrictedLink: "rd://link",
                              parsed: ParsedRelease(title: "Sherlock", season: 2, episode: 1,
                                                    resolution: "2160p", videoCodec: "x265"))
        return PlayerModel(request: Fixture.request(sources: [src]), engine: engine,
                           unrestrict: { _ in URL(string: "https://cdn/x.mkv")! },
                           recordProgress: { _, _, _, _ in }, subtitles: subs)
    }

    /// Drive a model to the point where a subtitle download can be requested, with a known runtime.
    private func started(_ subs: FakeSubtitleProvider,
                         engine: FakeVideoPlayerEngine) async -> PlayerModel {
        let m = model(subs, engine: engine)
        m.start()
        engine.emit(.time(PlaybackTime(position: 0, duration: 5400)))
        await m.waitForIdleForTesting()
        return m
    }

    @Test func a25fpsSubtitleIsStretchedOntoA23976File() async {
        let downloaded = writeSubtitle()
        let subs = FakeSubtitleProvider()
        subs.downloadedURL = downloaded
        subs.searchResults = [SubtitleResult(fileID: 1, language: "en", release: "Sherlock.PAL",
                                             fps: 25)]
        let engine = FakeVideoPlayerEngine()
        engine.videoFPS = 23.976
        let m = await started(subs, engine: engine)

        await m.requestSubtitle(language: "en")

        let attached = try! #require(engine.addedSubtitles.last)
        #expect(attached != downloaded)          // the cached download is not what was attached
        let text = try! String(contentsOf: attached, encoding: .utf8)
        // 3600s × 25/23.976 = 3753.75s — the 2m33s of drift the viewer was seeing, removed.
        #expect(text.contains("01:02:33,7"))
        #expect(m.subtitleRetimeFactor != nil)
    }

    @Test func theCachedDownloadItselfIsNeverRewritten() async {
        let downloaded = writeSubtitle()
        let subs = FakeSubtitleProvider()
        subs.downloadedURL = downloaded
        subs.searchResults = [SubtitleResult(fileID: 1, language: "en", fps: 25)]
        let engine = FakeVideoPlayerEngine()
        engine.videoFPS = 23.976
        let m = await started(subs, engine: engine)

        await m.requestSubtitle(language: "en")

        // Downloads are cached on disk by file_id. Correcting one in place would correct it AGAIN
        // on the next play, and would corrupt it for a different release sharing the subtitle.
        #expect(try! String(contentsOf: downloaded, encoding: .utf8) == Self.srt)
    }

    @Test func aSubtitleAlreadyOnTheFilesRateIsAttachedUntouched() async {
        let downloaded = writeSubtitle()
        let subs = FakeSubtitleProvider()
        subs.downloadedURL = downloaded
        subs.searchResults = [SubtitleResult(fileID: 1, language: "en", fps: 23.976)]
        let engine = FakeVideoPlayerEngine()
        engine.videoFPS = 23.976
        let m = await started(subs, engine: engine)

        await m.requestSubtitle(language: "en")

        #expect(engine.addedSubtitles.last == downloaded)
        #expect(m.subtitleRetimeFactor == nil)
    }

    @Test func anUnknownRateLeavesTheSubtitleAlone() async {
        // OpenSubtitles sends no fps for plenty of entries. Guessing a correction from nothing
        // would break subtitles that are currently fine.
        let downloaded = writeSubtitle()
        let subs = FakeSubtitleProvider()
        subs.downloadedURL = downloaded
        subs.searchResults = [SubtitleResult(fileID: 1, language: "en", fps: nil)]
        let engine = FakeVideoPlayerEngine()
        engine.videoFPS = 23.976
        let m = await started(subs, engine: engine)

        await m.requestSubtitle(language: "en")

        #expect(engine.addedSubtitles.last == downloaded)
        #expect(m.subtitleRetimeFactor == nil)
    }

    @Test func upNextFollowsTheCorrectedDialogueEnd() async {
        let downloaded = writeSubtitle()
        let subs = FakeSubtitleProvider()
        subs.downloadedURL = downloaded
        subs.searchResults = [SubtitleResult(fileID: 1, language: "en", fps: 25)]
        let engine = FakeVideoPlayerEngine()
        engine.videoFPS = 23.976
        let m = await started(subs, engine: engine)

        await m.requestSubtitle(language: "en")

        // Every cue moved, including the last one Up Next keys off — 3602s → 3755.8s. Left at the
        // uncorrected value the countdown would roll in two and a half minutes early.
        let end = try! #require(m.contentEndTime)
        #expect(abs(end - 3755.8) < 0.5)
    }
}
