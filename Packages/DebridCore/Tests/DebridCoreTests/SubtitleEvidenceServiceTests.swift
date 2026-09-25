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
        func recover() { lock.lock(); down = false; lock.unlock() }
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

    final class TitleBox: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: TitleSubtitleEvidence?
        func set(_ value: TitleSubtitleEvidence) { lock.lock(); stored = value; lock.unlock() }
        var value: TitleSubtitleEvidence? { lock.lock(); defer { lock.unlock() }; return stored }
    }

    final class Answer: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [SubtitleResult]?
        func set(_ value: [SubtitleResult]?) { lock.lock(); stored = value; lock.unlock() }
        var value: [SubtitleResult]? { lock.lock(); defer { lock.unlock() }; return stored }
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
        #expect(await eventually { calls.count("search") == 2 })
    }

    /// A day-old answer comes back at once and is refreshed behind it. A title page waited on
    /// OpenSubtitles every day before showing what it already knew — up to a minute when the
    /// service was slow, with Play focused and playing the wrong copy.
    @Test func aStaleAnswerComesBackAtOnceAndIsRefreshedBehindIt() async {
        let calls = Calls(), clock = Clock(), gate = Gate(), old = Self.result
        let new = SubtitleResult(fileID: 2, language: "he", release: "T.2024.2160p.WEB-DL")
        let svc = service(tempDir(), calls: calls, clock: clock, search: { _, _ in
            calls.hit("search")
            if calls.count("search") == 1 { return [old] }
            await gate.wait()
            return [old, new]
        })
        _ = await svc.hebrewResults(contentKey: "k", query: query, originalLanguage: "en")
        clock.advance(25 * 60 * 60)
        // The refresh is held open: the answer must arrive anyway. Asked from a task, so a
        // regression fails here instead of hanging the run.
        let answer = Answer()
        let query = self.query
        let asking = Task { answer.set(await svc.hebrewResults(contentKey: "k", query: query, originalLanguage: "en")) }
        #expect(await eventually { answer.value != nil })
        #expect(answer.value == [old])
        #expect(await eventually { gate.arrivals == 1 })
        gate.open()
        await asking.value
        #expect(await eventually { calls.count("search") == 2 })
        var refreshed: [SubtitleResult]?
        for _ in 0..<2000 where refreshed?.count != 2 {
            refreshed = await svc.storedHebrewResults(contentKey: "k")
            try? await Task.sleep(for: .milliseconds(1))
        }
        #expect(refreshed == [old, new])
    }

    /// The web's title page answers within its deadline from whatever is ready — here, what an
    /// earlier visit stored — while a hung search carries on behind it for the next load.
    @Test func aTitleAnswersWithinItsDeadlineWithWhatItHas() async {
        let calls = Calls(), gate = Gate(), dir = tempDir(), result = Self.result
        _ = await service(dir, calls: calls).records(for: [source("A")])
        let svc = service(dir, calls: calls, search: { _, _ in await gate.wait(); return [result] })
        let box = TitleBox(), a = source("A"), query = self.query
        let asking = Task {
            box.set(await svc.titleEvidence(for: [a], contentKey: "k", query: query,
                                            originalLanguage: "en", within: .milliseconds(200)))
        }
        #expect(await eventually { box.value != nil })       // answered while the search hangs
        #expect(box.value?.evidence.hebrew(forVersion: WatchKey.source(a)) == .builtIn)
        #expect(box.value?.hebrewResults == nil)
        gate.open()
        await asking.value
        let later = await svc.titleEvidence(for: [source("A")], contentKey: "k", query: query,
                                            originalLanguage: "en", within: .seconds(5))
        #expect(later.hebrewResults == [result])
    }

    /// The web's route has no language when TMDB failed. Both of titleEvidence's paths then use
    /// the stored one, so the pick for a film does not depend on which path answered.
    @Test func aTitleWithoutItsLanguageUsesTheStoredOne() async {
        let svc = service(tempDir(), calls: Calls())
        _ = await svc.hebrewResults(contentKey: "k", query: query, originalLanguage: "fr")
        let found = await svc.titleEvidence(for: [source("A")], contentKey: "k", query: query,
                                            originalLanguage: nil, within: .seconds(5))
        #expect(found.evidence.originalLanguage == "fr")
    }

    @Test func storedResultsNeverTouchTheNetwork() async {
        let calls = Calls()
        let svc = service(tempDir(), calls: calls, search: { _, _ in calls.hit("search"); return [Self.result] })
        #expect(await svc.storedHebrewResults(contentKey: "k") == nil)
        #expect(calls.count("search") == 0)
        _ = await svc.hebrewResults(contentKey: "k", query: query, originalLanguage: "en")
        #expect(await svc.storedHebrewResults(contentKey: "k") == [Self.result])
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

    /// A failure is not an answer: kept, it would read as "no Hebrew" for a day.
    @Test func aFailedSearchIsNotKeptAndIsAskedAgain() async {
        let calls = Calls(), network = Network(), result = Self.result
        network.fail()
        let svc = service(tempDir(), calls: calls, search: { _, _ in
            calls.hit("search")
            if network.isDown { throw Boom.offline }
            return [result]
        })
        #expect(await svc.hebrewResults(contentKey: "k", query: query, originalLanguage: "en") == nil)
        #expect(await svc.storedHebrewResults(contentKey: "k") == nil)
        network.recover()
        #expect(await svc.hebrewResults(contentKey: "k", query: query, originalLanguage: "en") == [result])
        #expect(calls.count("search") == 2)
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

    /// Leave a film with several unread versions for another film, and the new page's reads go
    /// next — not after every read the old page queued.
    @Test func theNewestReadIsServedFirst() async {
        let probed = Probed(), first = Gate(), rest = Gate()
        let svc = SubtitleEvidenceService(
            directory: tempDir(), search: nil,
            resolve: { link in ResolvedLink(url: URL(string: "https://cdn.example/\(link.dropFirst(5))")!, fileName: nil) },
            probe: { url in
                let name = url.lastPathComponent
                probed.add(name)
                if name == "A" { await first.wait() } else if name != "X" { await rest.wait() }
                return .tracks([])
            })
        let oldPage = Task { await svc.records(for: ["A", "B", "C"].map(source)) }   // A and B read; C queues
        #expect(await eventually { probed.all.count == 2 })
        let newPage = Task { await svc.records(for: [source("X")]) }                  // X queues after C
        try? await Task.sleep(for: .milliseconds(50))
        first.open()                                                                  // one slot frees
        #expect(await eventually { probed.all.contains("X") })                         // …and X takes it
        let order = probed.all
        #expect((order.firstIndex(of: "X") ?? .max) < (order.firstIndex(of: "C") ?? .max))
        rest.open()
        _ = await (oldPage.value, newPage.value)
    }

    final class Probed: @unchecked Sendable {
        private let lock = NSLock()
        private var names: [String] = []
        func add(_ name: String) { lock.lock(); names.append(name); lock.unlock() }
        var all: [String] { lock.lock(); defer { lock.unlock() }; return names }
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
        #expect(record?.origin == .unreadable)
        #expect(record?.fileName == "T.2024.1080p.WEB-DL.mkv")
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

    /// Home's Resume plays before any title page opens, so the player can report a file first.
    /// Its report has no forced flags and no frame rate: the header must still be read, and wins.
    @Test func aFileThePlayerReportedFirstIsStillRead() async {
        let calls = Calls()
        let forced = ContainerTrack(kind: .subtitle, language: "he", codec: "S_TEXT/UTF8", isForced: true)
        let svc = service(tempDir(), calls: calls, probe: { _ in calls.hit("probe"); return .tracks([forced]) })
        await svc.recordPlayback([MediaTrack(id: "spu/3", kind: .subtitle, name: "Hebrew",
                                             language: "he", codec: "subt")], for: source("A"))
        let record = await svc.records(for: [source("A")]).first?.value
        #expect(calls.count("probe") == 1)
        #expect(record?.origin == .header)
        #expect(record?.hebrewLevel == HebrewSubtitles.none)
        _ = await svc.records(for: [source("A")])
        #expect(calls.count("probe") == 1)          // a header read is final: never read again
    }

    /// A re-read that fails changes nothing: the player's report still counts, so the title page's
    /// badge, chip and Play pick do not vanish because Real-Debrid answered 503 once.
    @Test func aFailedReadKeepsWhatThePlayerReported() async {
        let calls = Calls()
        let svc = SubtitleEvidenceService(
            directory: tempDir(), search: nil,
            resolve: { _ in calls.hit("resolve"); throw Boom.offline },
            probe: { _ in .notMatroska })
        await svc.recordPlayback([MediaTrack(id: "spu/3", kind: .subtitle, name: "Hebrew",
                                             language: "he", codec: "subt")], for: source("A"))
        let record = await svc.records(for: [source("A")]).first?.value
        #expect(calls.count("resolve") == 1)
        #expect(record?.origin == .playback)
        #expect(record?.hebrewLevel == .builtIn)
    }

    /// An MP4 the player reported first: the read finds no Matroska header, keeps what the player
    /// saw, and still records the file's own name — the only place a HebSubs or TS tag lives.
    @Test func anMP4ThePlayerReportedFirstKeepsItsTracksAndGainsItsName() async {
        let calls = Calls()
        let svc = service(tempDir(), calls: calls, probe: { _ in calls.hit("probe"); return .notMatroska })
        await svc.recordPlayback([MediaTrack(id: "spu/3", kind: .subtitle, name: "Hebrew",
                                             language: "he", codec: "tx3g")], for: source("A"))
        let record = await svc.records(for: [source("A")]).first?.value
        #expect(record?.origin == .unreadable)
        #expect(record?.fileName == "T.2024.1080p.WEB-DL.mkv")
        #expect(record?.hebrewLevel == .builtIn)
        _ = await svc.records(for: [source("A")])
        #expect(calls.count("probe") == 1)
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
