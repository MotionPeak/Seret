import Testing
import Foundation
@testable import DebridCore

@Suite struct SubtitleEvidenceServiceTests {
    /// Counts what the service asked for, from inside @Sendable closures.
    final class Calls: @unchecked Sendable {
        private let lock = NSLock()
        private var counts: [String: Int] = [:]
        private var running = 0
        private var peakRunning = 0
        func hit(_ name: String) { lock.lock(); counts[name, default: 0] += 1; lock.unlock() }
        func count(_ name: String) -> Int { lock.lock(); defer { lock.unlock() }; return counts[name] ?? 0 }
        func enter() { lock.lock(); running += 1; peakRunning = max(peakRunning, running); lock.unlock() }
        func leave() { lock.lock(); running -= 1; lock.unlock() }
        var peak: Int { lock.lock(); defer { lock.unlock() }; return peakRunning }
    }

    final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var current = Date(timeIntervalSince1970: 1_000_000)
        var now: Date { lock.lock(); defer { lock.unlock() }; return current }
        func advance(_ seconds: TimeInterval) { lock.lock(); current += seconds; lock.unlock() }
    }

    /// Lets a test take the fake network down between two asks.
    final class Network: @unchecked Sendable {
        private let lock = NSLock()
        private var down = false
        var isDown: Bool { lock.lock(); defer { lock.unlock() }; return down }
        func fail() { lock.lock(); down = true; lock.unlock() }
    }

    enum Boom: Error { case offline }

    /// Holds fake reads open until the test lets them finish.
    final class Gate: @unchecked Sendable {
        private let lock = NSLock()
        private var waiting: [CheckedContinuation<Void, Never>] = []
        private var isOpen = false
        private var arrived = 0
        func wait() async {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                lock.lock()
                arrived += 1
                if isOpen {
                    lock.unlock()
                    continuation.resume()
                } else {
                    waiting.append(continuation)
                    lock.unlock()
                }
            }
        }
        func open() {
            lock.lock()
            isOpen = true
            let released = waiting
            waiting = []
            lock.unlock()
            released.forEach { $0.resume() }
        }
        var arrivals: Int { lock.lock(); defer { lock.unlock() }; return arrived }
    }

    /// Polls `condition` for up to two seconds — for asserting that something DID happen while
    /// something else is still held open.
    private func eventually(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<2000 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(1))
        }
        return condition()
    }

    private static let hebrewText = ContainerTrack(kind: .subtitle, language: "he", codec: "S_TEXT/UTF8")
    private static let result = SubtitleResult(fileID: 1, language: "he", release: "T.2024.1080p.WEB-DL")
    private let query = SubtitleQuery(tmdbID: 1, title: "T")

    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "evidence-\(UUID().uuidString)")
    }

    private func source(_ id: String) -> MediaSource {
        MediaSource(torrentID: id, fileID: 1, restrictedLink: "rd://\(id)",
                    parsed: ParsedRelease(title: "T", resolution: "1080p"))
    }

    private func service(_ dir: URL, calls: Calls, clock: Clock = Clock(),
                         search: SubtitleEvidenceService.Search? = nil,
                         probe: SubtitleEvidenceService.Probe? = nil) -> SubtitleEvidenceService {
        let track = Self.hebrewText
        return SubtitleEvidenceService(
            directory: dir,
            search: search,
            resolve: { link in
                calls.hit("resolve")
                return ResolvedLink(url: URL(string: "https://cdn.example/\(link.count)")!,
                                    fileName: "T.2024.1080p.WEB-DL.mkv")
            },
            probe: probe ?? { _ in calls.hit("probe"); return .tracks([track]) },
            now: { clock.now })
    }

    // MARK: search

    @Test func aTitleIsSearchedOnceADay() async {
        let calls = Calls(), clock = Clock(), result = Self.result
        let svc = service(tempDir(), calls: calls, clock: clock,
                          search: { _, languages in
                              calls.hit("search")
                              #expect(languages == ["he"])
                              return [result]
                          })
        _ = await svc.hebrewResults(contentKey: "movie:tmdb:1", query: query, originalLanguage: "en")
        _ = await svc.hebrewResults(contentKey: "movie:tmdb:1", query: query, originalLanguage: "en")
        #expect(calls.count("search") == 1)
        clock.advance(25 * 60 * 60)
        _ = await svc.hebrewResults(contentKey: "movie:tmdb:1", query: query, originalLanguage: "en")
        #expect(calls.count("search") == 2)
    }

    @Test func aFailedSearchFallsBackToTheLastAnswer() async {
        let clock = Clock(), network = Network(), result = Self.result
        let svc = service(tempDir(), calls: Calls(), clock: clock,
                          search: { _, _ in
                              if network.isDown { throw Boom.offline }
                              return [result]
                          })
        let first = await svc.hebrewResults(contentKey: "k", query: query, originalLanguage: "en")
        clock.advance(25 * 60 * 60)          // stale, so the next ask goes to the network…
        network.fail()                       // …which is down
        let second = await svc.hebrewResults(contentKey: "k", query: query, originalLanguage: "en")
        #expect(first == [result])
        #expect(second == [result])
    }

    @Test func withNoSearchClientOnlyStoredAnswersComeBack() async {
        let svc = service(tempDir(), calls: Calls())
        #expect(await svc.hebrewResults(contentKey: "k", query: query, originalLanguage: "en") == nil)
    }

    /// Home and the web read only what was stored. The film's language used to live inside a
    /// successful search, so with no OpenSubtitles key — or a search that failed — they lost it,
    /// and with it the Hebrew-film and dub guards the title page applies.
    @Test func theFilmsLanguageIsKeptWithNoSearchToAsk() async {
        let svc = service(tempDir(), calls: Calls())
        _ = await svc.hebrewResults(contentKey: "k", query: query, originalLanguage: "he")
        #expect(await svc.storedEvidence(for: [source("A")], contentKey: "k").originalLanguage == "he")
    }

    @Test func theFilmsLanguageIsKeptWhenTheSearchFails() async {
        let svc = service(tempDir(), calls: Calls(), search: { _, _ in throw Boom.offline })
        _ = await svc.hebrewResults(contentKey: "k", query: query, originalLanguage: "iw")
        #expect(await svc.storedEvidence(for: [source("A")], contentKey: "k").originalLanguage == "he")
    }

    @Test func onlyHebrewResultsAreKept() async {
        let svc = service(tempDir(), calls: Calls(),
                          search: { _, _ in [Self.result, SubtitleResult(fileID: 2, language: "en")] })
        #expect(await svc.hebrewResults(contentKey: "k", query: query, originalLanguage: "en") == [Self.result])
    }

    // MARK: records

    @Test func onlyUnknownFilesAreRead() async {
        let calls = Calls(), dir = tempDir()
        let svc = service(dir, calls: calls)
        let first = await svc.records(for: [source("A"), source("B")])
        #expect(first.count == 2)
        #expect(calls.count("probe") == 2)
        _ = await svc.records(for: [source("A"), source("B")])
        #expect(calls.count("probe") == 2)
        #expect(first[WatchKey.source(source("A"))]?.hebrewLevel == .builtIn)
    }

    @Test func recordsSurviveARelaunch() async {
        let calls = Calls(), dir = tempDir()
        _ = await service(dir, calls: calls).records(for: [source("A")])
        _ = await service(dir, calls: calls).records(for: [source("A")])
        #expect(calls.count("probe") == 1)
    }

    @Test func aTransientFailureIsTriedAgainNextTime() async {
        let calls = Calls()
        let svc = service(tempDir(), calls: calls, probe: { _ in calls.hit("probe"); return nil })
        #expect(await svc.records(for: [source("A")]).isEmpty)
        _ = await svc.records(for: [source("A")])
        #expect(calls.count("probe") == 2)
    }

    @Test func aFileThatIsNotMatroskaIsNotReadTwice() async {
        let calls = Calls()
        let svc = service(tempDir(), calls: calls, probe: { _ in calls.hit("probe"); return .notMatroska })
        let records = await svc.records(for: [source("A")])
        #expect(records.first?.value.origin == .unreadable)
        #expect(records.first?.value.fileName == "T.2024.1080p.WEB-DL.mkv")
        _ = await svc.records(for: [source("A")])
        #expect(calls.count("probe") == 1)
    }

    @Test func neverMoreThanTwoReadsAtOnce() async {
        let calls = Calls()
        let track = Self.hebrewText
        let svc = service(tempDir(), calls: calls, probe: { _ in
            calls.enter()
            try? await Task.sleep(for: .milliseconds(20))
            calls.leave()
            return .tracks([track])
        })
        _ = await svc.records(for: ["A", "B", "C", "D", "E"].map(source))
        #expect(calls.peak <= 2)
    }

    /// The limit is the service's, not each caller's: two title pages (or two web requests) at
    /// once used to run two reads EACH.
    @Test func theReadLimitHoldsAcrossCallers() async {
        let calls = Calls()
        let track = Self.hebrewText
        let svc = service(tempDir(), calls: calls, probe: { _ in
            calls.enter()
            try? await Task.sleep(for: .milliseconds(20))
            calls.leave()
            return .tracks([track])
        })
        async let one = svc.records(for: ["A", "B", "C"].map(source))
        async let two = svc.records(for: ["D", "E", "F"].map(source))
        _ = await (one, two)
        #expect(calls.peak <= 2)
    }

    /// A slow read must not hold up the next one: reads go a couple at a time as slots free up,
    /// not in batches that each wait for their slowest.
    @Test func aSlowReadDoesNotHoldUpTheRest() async {
        let calls = Calls(), gate = Gate()
        let track = Self.hebrewText
        let slow = source("A")
        // The fake resolver names each URL after its link's length: A's is the only 6-long link.
        let svc = service(tempDir(), calls: calls, probe: { url in
            calls.hit("probe")
            if url.absoluteString.hasSuffix("/\(slow.restrictedLink.count)") { await gate.wait() }
            return .tracks([track])
        })
        let reading = Task { await svc.records(for: [slow, source("B2"), source("C3")]) }
        #expect(await eventually { calls.count("probe") == 3 })
        gate.open()
        #expect(await reading.value.count == 3)
    }

    // MARK: playback + stored

    @Test func playbackNeverChangesAHeaderRead() async {
        let forced = ContainerTrack(kind: .subtitle, language: "he", codec: "S_TEXT/UTF8", isForced: true)
        let svc = service(tempDir(), calls: Calls(), probe: { _ in .tracks([forced]) })
        _ = await svc.records(for: [source("A")])
        await svc.recordPlayback([MediaTrack(id: "spu/2", kind: .subtitle, name: "Hebrew",
                                             language: "he", codec: "subt")], for: source("A"))
        let record = await svc.records(for: [source("A")]).first?.value
        #expect(record?.origin == .header)
        #expect(record?.hebrewLevel == HebrewSubtitles.none)
    }

    /// Playback can land while the header is being read. The header is the file's own index and
    /// wins; a read that found nothing never erases what playback saw.
    @Test func aHeaderReadThatLandsAfterPlaybackReplacesIt() async {
        let gate = Gate()
        let track = Self.hebrewText
        let svc = service(tempDir(), calls: Calls(), probe: { _ in await gate.wait(); return .tracks([track]) })
        let reading = Task { await svc.records(for: [source("A")]) }
        #expect(await eventually { gate.arrivals == 1 })
        await svc.recordPlayback([MediaTrack(id: "a/1", kind: .audio, name: "English", language: "en")],
                                 for: source("A"))
        gate.open()
        #expect(await reading.value.first?.value.origin == .header)
        #expect(await svc.records(for: [source("A")]).first?.value.origin == .header)
    }

    @Test func anUnreadableHeaderNeverErasesWhatPlaybackSaw() async {
        let gate = Gate()
        let svc = service(tempDir(), calls: Calls(), probe: { _ in await gate.wait(); return .notMatroska })
        let reading = Task { await svc.records(for: [source("A")]) }
        #expect(await eventually { gate.arrivals == 1 })
        await svc.recordPlayback([MediaTrack(id: "spu/3", kind: .subtitle, name: "Hebrew",
                                             language: "he", codec: "subt")], for: source("A"))
        gate.open()
        let record = await reading.value.first?.value
        #expect(record?.origin == .playback)
        #expect(record?.hebrewLevel == .builtIn)
    }

    /// Each report is a read-modify-write of the stored record. Two landing together used to read
    /// the same old record and the second write erased the first.
    @Test func playbackReportsLandingTogetherAllLand() async {
        let svc = service(tempDir(), calls: Calls(), probe: { _ in .notMatroska })
        let a = source("A")
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<20 {
                group.addTask {
                    await svc.recordPlayback([MediaTrack(id: "a/\(i)", kind: .audio, name: "A\(i)",
                                                         language: "en", codec: "c\(i)")], for: a)
                }
            }
        }
        #expect(await svc.records(for: [source("A")]).first?.value.tracks.count == 20)
    }

    @Test func whatPlaybackSawIsKeptAndNoReadFollows() async {
        let calls = Calls()
        let svc = service(tempDir(), calls: calls)
        await svc.recordPlayback([MediaTrack(id: "spu/3", kind: .subtitle, name: "Hebrew",
                                             language: "he", codec: "subt")], for: source("A"))
        let records = await svc.records(for: [source("A")])
        #expect(calls.count("probe") == 0)
        #expect(records.first?.value.origin == .playback)
        #expect(records.first?.value.hebrewLevel == .builtIn)
    }

    @Test func aDownloadedSubtitleIsNotRecordedAsTheFiles() async {
        let calls = Calls()
        let svc = service(tempDir(), calls: calls)
        await svc.recordPlayback([MediaTrack(id: "x/spu/0", kind: .subtitle, name: "Track 1",
                                             language: "he", isExternal: true)], for: source("A"))
        _ = await svc.records(for: [source("A")])
        #expect(calls.count("probe") == 1)     // nothing was stored, so the file was read
    }

    @Test func storedEvidenceNeverTouchesTheNetwork() async {
        let calls = Calls(), dir = tempDir()
        let result = SubtitleResult(fileID: 1, language: "he", release: "T.1080p")
        let warm = service(dir, calls: calls, search: { _, _ in [result] })
        _ = await warm.hebrewResults(contentKey: "movie:tmdb:1", query: query, originalLanguage: "en")
        _ = await warm.records(for: [source("A")])
        let before = (calls.count("search"), calls.count("resolve"), calls.count("probe"))

        let cold = service(dir, calls: calls, search: { _, _ in calls.hit("search"); return [] })
        let evidence = await cold.storedEvidence(for: [source("A"), source("B")], contentKey: "movie:tmdb:1")
        #expect((calls.count("search"), calls.count("resolve"), calls.count("probe")) == before)
        #expect(evidence.hebrew(forVersion: WatchKey.source(source("A"))) == .builtIn)
        #expect(evidence.originalLanguage == "en")
    }
}
