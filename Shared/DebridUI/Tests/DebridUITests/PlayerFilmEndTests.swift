import Testing
import Foundation
@testable import DebridUI
import DebridCore

/// Where a film ends, when nothing the viewer chose says so.
///
/// The rating prompt asks at the moment the film counts as watched. With a subtitle the viewer
/// downloaded, that is the last spoken line. But a film watched with an EMBEDDED subtitle — or
/// none — told the player nothing, and fell back to an estimate. Halfway in, the player now asks
/// for itself: the credits timestamp TheIntroDB keeps, and failing that, a subtitle fetched only to
/// read where its dialogue ends. Nothing is attached; the viewer sees no change.
@MainActor
@Suite struct PlayerFilmEndTests {

    /// Two hours. The estimate alone says watched at 6900 (five minutes out).
    private let feature: Double = 7200

    private final class Recorder: @unchecked Sendable {
        var finishedFlags: [Bool] = []
    }

    final class FakeCredits: CreditsLocating, @unchecked Sendable {
        var start: Double?
        var error: Error?
        private(set) var asked: [(tmdbID: Int, duration: Double)] = []
        func creditsStart(tmdbID: Int, durationSeconds: Double) async throws -> Double? {
            asked.append((tmdbID, durationSeconds))
            if let error { throw error }
            return start
        }
    }

    /// An SRT whose last line ends at `seconds`.
    private static func srt(lastLineEndingAt seconds: Double) -> String {
        func stamp(_ t: Double) -> String {
            let ms = Int((t * 1000).rounded())
            return String(format: "%02d:%02d:%02d,%03d", ms / 3_600_000, ms / 60_000 % 60,
                          ms / 1000 % 60, ms % 1000)
        }
        return """
        1
        00:01:00,000 --> 00:01:02,000
        First line.

        2
        \(stamp(seconds - 2)) --> \(stamp(seconds))
        Last line.
        """
    }

    /// The file's own index, as `ContainerProbe.index` would read it.
    final class FakeIndex: @unchecked Sendable {
        var index: MatroskaIndex?
        private(set) var asked: [URL] = []
        func read(_ url: URL) -> MatroskaIndex? { asked.append(url); return index }

        /// An English track of a film's worth of lines, the last leaving the screen at `lastLine`.
        static func english(lastLine: Double, chapters: [MatroskaIndex.Chapter] = []) -> MatroskaIndex {
            let lines = stride(from: 300.0, to: lastLine, by: 5).map { $0 } + [lastLine]
            return MatroskaIndex(
                subtitles: [.init(track: ContainerTrack(kind: .subtitle, language: "en", name: "English"),
                                  lineEnds: lines)],
                chapters: chapters)
        }
    }

    private func model(_ recorder: Recorder, engine: FakeVideoPlayerEngine,
                       subtitles: FakeSubtitleProvider?, credits: FakeCredits? = nil,
                       index: FakeIndex? = nil,
                       request: PlaybackRequest = Fixture.request()) -> PlayerModel {
        PlayerModel(request: request, engine: engine,
                    unrestrict: { _ in URL(string: "https://cdn/x.mkv")! },
                    recordProgress: { _, _, _, _, finished in
                        recorder.finishedFlags.append(finished)
                    },
                    subtitles: subtitles,
                    credits: credits,
                    readIndex: index.map { fake in { @Sendable url in fake.read(url) } })
    }

    private func tick(_ m: PlayerModel, _ engine: FakeVideoPlayerEngine, at position: Double,
                      duration: Double? = nil) async {
        engine.emit(.time(PlaybackTime(position: position, duration: duration ?? feature)))
        await m.waitForIdleForTesting()
    }

    private func subtitles(lastLineEndingAt end: Double) -> FakeSubtitleProvider {
        let subs = FakeSubtitleProvider()
        subs.searchResults = [SubtitleResult(fileID: 9, language: "en", release: "Film.2024")]
        subs.downloadedText = Self.srt(lastLineEndingAt: end)
        return subs
    }

    // MARK: - The subtitle read for its timing

    /// The film's last line is at 1:56:40 — after the estimate. Without the fetch, the film counted
    /// as watched (and asked for a rating) while that scene was still playing.
    @Test func aFilmWithNoSubtitleIsOverWhenAFetchedSubtitleSaysTheDialogueEnds() async {
        let recorder = Recorder(), engine = FakeVideoPlayerEngine()
        let subs = subtitles(lastLineEndingAt: 7000)
        let m = model(recorder, engine: engine, subtitles: subs)
        m.start(); await m.waitForIdleForTesting()

        await tick(m, engine, at: 3600)                 // halfway: the player asks
        #expect(subs.searchedLanguages.count == 1)
        #expect(m.contentEndTime == 7000)

        await tick(m, engine, at: 6950)
        #expect(recorder.finishedFlags.last == false, "still in the final scene")
        await tick(m, engine, at: 7001)
        #expect(recorder.finishedFlags.last == true)
        await m.teardown()
    }

    /// The fetch is for its timing only: nothing is attached, and the subtitle rows stay as the
    /// viewer left them.
    @Test func theTimingSubtitleIsNeverShown() async {
        let recorder = Recorder(), engine = FakeVideoPlayerEngine()
        let subs = subtitles(lastLineEndingAt: 7000)
        let m = model(recorder, engine: engine, subtitles: subs)
        m.start(); await m.waitForIdleForTesting()

        await tick(m, engine, at: 3600)

        #expect(engine.addedSubtitles.isEmpty)
        #expect(m.subtitleRows.allSatisfy { $0.state == .idle })
        #expect(m.subtitleCues.isEmpty)
        await m.teardown()
    }

    /// A film abandoned in its first act spends no OpenSubtitles quota.
    @Test func nothingIsFetchedBeforeHalfway() async {
        let recorder = Recorder(), engine = FakeVideoPlayerEngine()
        let subs = subtitles(lastLineEndingAt: 7000)
        let credits = FakeCredits()
        let m = model(recorder, engine: engine, subtitles: subs, credits: credits)
        m.start(); await m.waitForIdleForTesting()

        await tick(m, engine, at: 3500)

        #expect(subs.searchedLanguages.isEmpty)
        #expect(credits.asked.isEmpty)
        await m.teardown()
    }

    @Test func itAsksOnceAFilm() async {
        let recorder = Recorder(), engine = FakeVideoPlayerEngine()
        let subs = subtitles(lastLineEndingAt: 7000)
        let m = model(recorder, engine: engine, subtitles: subs)
        m.start(); await m.waitForIdleForTesting()

        await tick(m, engine, at: 3600)
        await tick(m, engine, at: 3601)
        await tick(m, engine, at: 5000)

        #expect(subs.searchedLanguages.count == 1)
        #expect(subs.downloadedResults.count == 1)
        await m.teardown()
    }

    /// A subtitle the viewer downloaded already said where the dialogue ends.
    @Test func aSubtitleAlreadyLoadedIsNotFetchedAgain() async {
        let recorder = Recorder(), engine = FakeVideoPlayerEngine()
        let subs = subtitles(lastLineEndingAt: 7000)
        let m = model(recorder, engine: engine, subtitles: subs)
        m.start(); await m.waitForIdleForTesting()
        m.contentEndTime = 6800

        await tick(m, engine, at: 3600)

        #expect(subs.searchedLanguages.isEmpty)
        #expect(m.contentEndTime == 6800)
        await m.teardown()
    }

    /// The rating prompt is for films; an episode's watched mark stays on the estimate rather than
    /// spending a download on every episode of a season.
    @Test func episodesAreNotMeasured() async {
        let recorder = Recorder(), engine = FakeVideoPlayerEngine()
        let subs = subtitles(lastLineEndingAt: 2500)
        let credits = FakeCredits()
        let m = model(recorder, engine: engine, subtitles: subs, credits: credits,
                      request: Fixture.showRequest(playingEpisode: 1))
        m.start(); await m.waitForIdleForTesting()

        await tick(m, engine, at: 2000, duration: 2700)

        #expect(subs.searchedLanguages.isEmpty)
        #expect(credits.asked.isEmpty)
        await m.teardown()
    }

    /// Out of quota is not a reason to bother the viewer: the estimate stands.
    @Test func aDailyCapLeavesTheEstimate() async {
        let recorder = Recorder(), engine = FakeVideoPlayerEngine()
        let subs = subtitles(lastLineEndingAt: 7000)
        subs.downloadError = SubtitleError.dailyCapReached(resetTime: nil)
        let m = model(recorder, engine: engine, subtitles: subs)
        m.start(); await m.waitForIdleForTesting()

        await tick(m, engine, at: 3600)
        #expect(m.contentEndTime == nil)
        #expect(m.subtitleRows.allSatisfy { $0.state == .idle })

        await tick(m, engine, at: 6901)
        #expect(recorder.finishedFlags.last == true)
        await m.teardown()
    }

    // MARK: - The file's own subtitle

    /// The file playing knows best: its own English subtitle is timed to THIS file, so there is
    /// nothing to correct and nothing to download.
    @Test func theFilesOwnSubtitleSaysWhereTheFilmEnds() async {
        let recorder = Recorder(), engine = FakeVideoPlayerEngine()
        let subs = subtitles(lastLineEndingAt: 6000)
        let credits = FakeCredits()
        let index = FakeIndex()
        index.index = FakeIndex.english(lastLine: 7000)
        let m = model(recorder, engine: engine, subtitles: subs, credits: credits, index: index)
        m.start(); await m.waitForIdleForTesting()

        await tick(m, engine, at: 3600)

        #expect(index.asked == [URL(string: "https://cdn/x.mkv")!])
        #expect(m.contentEndTime == 7000)
        #expect(subs.searchedLanguages.isEmpty, "no download")
        #expect(credits.asked.isEmpty, "no database")
        await tick(m, engine, at: 6999)
        #expect(recorder.finishedFlags.last == false)
        await tick(m, engine, at: 7000)
        #expect(recorder.finishedFlags.last == true)
        await m.teardown()
    }

    @Test func anEndCreditsChapterInTheFileIsWhereTheFilmIsOver() async {
        let recorder = Recorder(), engine = FakeVideoPlayerEngine()
        let index = FakeIndex()
        index.index = FakeIndex.english(lastLine: 6900, chapters: [.init(start: 6950, title: "End Credits")])
        let m = model(recorder, engine: engine, subtitles: nil, index: index)
        m.start(); await m.waitForIdleForTesting()

        await tick(m, engine, at: 3600)

        #expect(m.creditsStartTime == 6950)
        await tick(m, engine, at: 6949)
        #expect(recorder.finishedFlags.last == false)
        await tick(m, engine, at: 6950)
        #expect(recorder.finishedFlags.last == true)
        await m.teardown()
    }

    /// A subtitle the viewer downloaded is another release's timing; the file's own wins, even
    /// when the download comes later.
    @Test func theFilesOwnTimingIsNotReplacedByADownload() async {
        let recorder = Recorder(), engine = FakeVideoPlayerEngine()
        let subs = subtitles(lastLineEndingAt: 6500)
        let index = FakeIndex()
        index.index = FakeIndex.english(lastLine: 7000)
        let m = model(recorder, engine: engine, subtitles: subs, index: index)
        m.start(); await m.waitForIdleForTesting()
        m.contentEndTime = 6500                         // downloaded before halfway

        await tick(m, engine, at: 3600)
        #expect(m.contentEndTime == 7000)

        await m.requestSubtitle(language: "en")         // …and another download after
        #expect(m.contentEndTime == 7000)
        await m.teardown()
    }

    /// Good Will Hunting: the file's English track runs on through the credits song, so it cannot
    /// say where the film stopped. A subtitle from another release would be guessing too — the
    /// database is still asked, then the estimate stands.
    @Test func aFileWhoseSubtitleRunsIntoTheCreditsFallsBackWithoutADownload() async {
        let recorder = Recorder(), engine = FakeVideoPlayerEngine()
        let subs = subtitles(lastLineEndingAt: 6800)
        let credits = FakeCredits()
        let index = FakeIndex()
        index.index = FakeIndex.english(lastLine: feature - 10)
        let m = model(recorder, engine: engine, subtitles: subs, credits: credits, index: index)
        m.start(); await m.waitForIdleForTesting()

        await tick(m, engine, at: 3600)

        #expect(m.contentEndTime == nil)
        #expect(credits.asked.count == 1)
        #expect(subs.searchedLanguages.isEmpty)
        await tick(m, engine, at: feature - 5 * 60)
        #expect(recorder.finishedFlags.last == true)
        await m.teardown()
    }

    /// An MP4, or a file with no index: everything else is tried, as before.
    @Test func aFileWithNoIndexFallsBackToTheDatabaseThenADownload() async {
        let recorder = Recorder(), engine = FakeVideoPlayerEngine()
        let subs = subtitles(lastLineEndingAt: 7000)
        let credits = FakeCredits()
        let index = FakeIndex()
        let m = model(recorder, engine: engine, subtitles: subs, credits: credits, index: index)
        m.start(); await m.waitForIdleForTesting()

        await tick(m, engine, at: 3600)

        #expect(index.asked.count == 1)
        #expect(credits.asked.count == 1)
        #expect(m.contentEndTime == 7000)
        await m.teardown()
    }

    // MARK: - Leaving

    /// Six minutes from the end with nothing known about where the film ends: the estimate says
    /// "still on", but someone who stops there has seen it — and was never logged.
    @Test func leavingInTheCreditsWithNothingKnownCountsAsWatched() async {
        let recorder = Recorder(), engine = FakeVideoPlayerEngine()
        let m = model(recorder, engine: engine, subtitles: nil)
        m.start(); await m.waitForIdleForTesting()
        engine.emit(.state(.playing))
        await tick(m, engine, at: feature - 361)
        await tick(m, engine, at: feature - 360)
        #expect(recorder.finishedFlags.last == false)

        await m.teardown()

        #expect(recorder.finishedFlags.last == true)
    }

    /// …but with the last line known to be later, stopping there is stopping before the end.
    @Test func leavingBeforeAKnownLastLineIsNotWatched() async {
        let recorder = Recorder(), engine = FakeVideoPlayerEngine()
        let m = model(recorder, engine: engine, subtitles: nil)
        m.start(); await m.waitForIdleForTesting()
        m.contentEndTime = feature - 120
        engine.emit(.state(.playing))
        await tick(m, engine, at: feature - 361)
        await tick(m, engine, at: feature - 360)

        await m.teardown()

        #expect(recorder.finishedFlags.last == false)
    }

    /// Backgrounding the app is not leaving the film — it comes back to the same place.
    @Test func leavingTheForegroundIsNotLeavingTheFilm() async {
        let recorder = Recorder(), engine = FakeVideoPlayerEngine()
        let m = model(recorder, engine: engine, subtitles: nil)
        m.start(); await m.waitForIdleForTesting()
        engine.emit(.state(.playing))
        await tick(m, engine, at: feature - 361)
        await tick(m, engine, at: feature - 360)

        await m.appDidLeaveForeground()

        #expect(recorder.finishedFlags.last == false)
        await m.teardown()
    }

    // MARK: - The credits database

    @Test func whereTheDatabaseSaysTheCreditsStartIsWhereTheFilmIsOver() async {
        let recorder = Recorder(), engine = FakeVideoPlayerEngine()
        let credits = FakeCredits()
        credits.start = 7050
        let m = model(recorder, engine: engine, subtitles: nil, credits: credits)
        m.start(); await m.waitForIdleForTesting()

        await tick(m, engine, at: 3600)
        #expect(credits.asked.first?.tmdbID == 693134)
        #expect(credits.asked.first?.duration == feature)

        await tick(m, engine, at: 7000)
        #expect(recorder.finishedFlags.last == false)
        await tick(m, engine, at: 7050)
        #expect(recorder.finishedFlags.last == true)
        await m.teardown()
    }

    /// The credits are later than any line of dialogue, so with them known a subtitle could only
    /// add an earlier answer — not worth a download.
    @Test func knownCreditsSpendNoSubtitleDownload() async {
        let recorder = Recorder(), engine = FakeVideoPlayerEngine()
        let subs = subtitles(lastLineEndingAt: 7000)
        let credits = FakeCredits()
        credits.start = 7050
        let m = model(recorder, engine: engine, subtitles: subs, credits: credits)
        m.start(); await m.waitForIdleForTesting()

        await tick(m, engine, at: 3600)

        #expect(subs.searchedLanguages.isEmpty)
        await m.teardown()
    }

    /// Most films are not in the database; the subtitle is the next thing to ask.
    @Test func aFilmTheDatabaseDoesNotKnowFallsBackToTheSubtitle() async {
        let recorder = Recorder(), engine = FakeVideoPlayerEngine()
        let subs = subtitles(lastLineEndingAt: 7000)
        let credits = FakeCredits()
        credits.error = URLError(.notConnectedToInternet)
        let m = model(recorder, engine: engine, subtitles: subs, credits: credits)
        m.start(); await m.waitForIdleForTesting()

        await tick(m, engine, at: 3600)

        #expect(m.contentEndTime == 7000)
        await m.teardown()
    }

    /// Timestamps for a different cut are no evidence about this file, and must not stop the
    /// subtitle from being asked.
    @Test func implausiblyEarlyCreditsStillAskTheSubtitle() async {
        let recorder = Recorder(), engine = FakeVideoPlayerEngine()
        let subs = subtitles(lastLineEndingAt: 7000)
        let credits = FakeCredits()
        credits.start = 2000
        let m = model(recorder, engine: engine, subtitles: subs, credits: credits)
        m.start(); await m.waitForIdleForTesting()

        await tick(m, engine, at: 3600)

        #expect(subs.searchedLanguages.count == 1)
        #expect(m.contentEndTime == 7000)
        await m.teardown()
    }
}
