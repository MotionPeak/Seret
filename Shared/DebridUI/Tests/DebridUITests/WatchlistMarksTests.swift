import Testing
import Foundation
@testable import DebridUI
@testable import DebridCore

/// Lets a test hold a fake inside `toggle` and look at the UI state while the write is in flight.
///
/// A sleep would be the easy way and the wrong one: it makes the test slow when it passes and flaky
/// when the machine is busy. This blocks until the test says so, and nothing else.
private actor Gate {
    private var entered: CheckedContinuation<Void, Never>?
    private var isEntered = false
    private var release: CheckedContinuation<Void, Never>?

    func arrive() async {
        isEntered = true
        entered?.resume()
        entered = nil
        await withCheckedContinuation { release = $0 }
    }

    func waitForArrival() async {
        if isEntered { return }
        await withCheckedContinuation { entered = $0 }
    }

    func open() { release?.resume(); release = nil }
}

private final class Spy: @unchecked Sendable {
    private let lock = NSLock()
    private var _added: [WatchlistFilm] = []
    private var _removed: [String] = []
    private var _drains = 0

    var added: [WatchlistFilm] { lock.withLock { _added } }
    var removed: [String] { lock.withLock { _removed } }
    var drains: Int { lock.withLock { _drains } }

    func add(_ film: WatchlistFilm) { lock.withLock { _added.append(film) } }
    func remove(_ slug: String) { lock.withLock { _removed.append(slug) } }
    func drain() { lock.withLock { _drains += 1 } }
}

@MainActor
@Suite struct WatchlistMarksTests {
    private let heat = WatchlistFilm(tmdbID: 949, title: "Heat", year: 1995, posterPath: "/h.jpg")

    private func crawled(tmdbID: Int, slug: String, removed: Bool = false,
                         removalPushed: Bool = false) -> WatchlistEntry {
        WatchlistEntry(slug: slug, name: "Film (1995)", year: 1995, position: 0, tmdbID: tmdbID,
                       resolvedAt: Date(),
                       removedAt: removed ? Date() : nil,
                       removalPushedAt: removalPushed ? Date() : nil)
    }

    private func marks(mirror: [WatchlistEntry] = [],
                       after: [WatchlistEntry]? = nil,
                       settled: [WatchlistEntry]? = nil,
                       relay: WatchlistPushRelay.Outcome = .init(pushed: 1, failed: 0),
                       spy: Spy = Spy(),
                       gate: Gate? = nil) -> WatchlistMarks {
        // Three views of the mirror in sequence: as it starts, straight after the write, and once
        // the relay has had its turn. A test that could not vary the last one could not tell a
        // pushed change from one still waiting for the server.
        let reads = MirrorReads(initial: mirror, afterWrite: after ?? mirror,
                                afterRelay: settled ?? after ?? mirror)
        return WatchlistMarks(
            entries: { await reads.next() },
            add: { film in
                if let gate { await gate.arrive() }
                spy.add(film)
                return await reads.next()
            },
            remove: { slug in
                if let gate { await gate.arrive() }
                spy.remove(slug)
                return await reads.next()
            },
            relay: { spy.drain(); return relay })
    }

    /// Hands back `initial`, then `afterWrite`, then `afterRelay` for everything after.
    private actor MirrorReads {
        private var queue: [[WatchlistEntry]]
        private let last: [WatchlistEntry]
        init(initial: [WatchlistEntry], afterWrite: [WatchlistEntry], afterRelay: [WatchlistEntry]) {
            queue = [initial, afterWrite]
            last = afterRelay
        }
        func next() -> [WatchlistEntry] { queue.isEmpty ? last : queue.removeFirst() }
    }

    @Test func seedsFromTheMirror() async {
        let sut = marks(mirror: [crawled(tmdbID: 949, slug: "heat"),
                                 crawled(tmdbID: 1637, slug: "speed", removed: true)])
        await sut.load()

        #expect(sut.contains(tmdbID: 949))
        // Removed here: the owner took it off, so the control must not read as "on the watchlist".
        #expect(!sut.contains(tmdbID: 1637))
    }

    /// The mark has to flip on the press, not when the disk answers. A long-press that looked
    /// unchanged for a beat is a long-press the owner repeats, which toggles it straight back.
    @Test func theMarkFlipsBeforeTheWriteFinishes() async {
        let gate = Gate()
        let sut = marks(after: [crawled(tmdbID: 949, slug: "tmdb-949")], gate: gate)

        let toggling = Task { await sut.toggle(film: heat) }
        await gate.waitForArrival()
        #expect(sut.contains(tmdbID: 949))

        await gate.open()
        await toggling.value
        #expect(sut.contains(tmdbID: 949))
    }

    /// The store gets the last word. An add the mirror refused must not leave a mark saying it
    /// worked — that is how a screen ends up lying about what it holds.
    @Test func theStoreWinsWhenItDisagrees() async {
        let sut = marks(after: [])          // the write changed nothing
        await sut.toggle(film: heat)

        #expect(!sut.contains(tmdbID: 949))
    }

    /// Removal is by slug, and the mirror's real slug is the one Letterboxd knows. Guessing the
    /// placeholder for a crawled film would hit no row at all.
    @Test func removingUsesTheSlugTheMirrorHolds() async {
        let spy = Spy()
        let sut = marks(mirror: [crawled(tmdbID: 949, slug: "heat-1995")], after: [], spy: spy)
        await sut.load()

        await sut.toggle(film: heat)

        #expect(spy.removed == ["heat-1995"])
        #expect(spy.added.isEmpty)
        #expect(!sut.contains(tmdbID: 949))
    }

    @Test func addingPassesTheWholeFilmThrough() async {
        let spy = Spy()
        let sut = marks(after: [crawled(tmdbID: 949, slug: "tmdb-949")], spy: spy)

        await sut.toggle(film: heat)

        #expect(spy.added == [heat])
        #expect(spy.drains == 1)
    }

    @Test func aLandedAddSaysSo() async {
        var pushed = WatchlistEntry.locallyAdded(tmdbID: 949, title: "Heat", year: 1995,
                                                 posterPath: nil, position: -1)
        pushed.addPushedAt = Date()
        let sut = marks(after: [pushed], settled: [pushed])

        await sut.toggle(film: heat)

        let outcome = try? #require(sut.lastOutcome)
        #expect(outcome?.tmdbID == 949)
        #expect(outcome?.isFailure == false)
        #expect(outcome?.message.contains("Letterboxd") == true)
        #expect(outcome?.message.lowercased().contains("added") == true)
    }

    @Test func aLandedRemovalSaysRemoved() async {
        let sut = marks(mirror: [crawled(tmdbID: 949, slug: "heat")],
                        after: [crawled(tmdbID: 949, slug: "heat", removed: true)],
                        settled: [crawled(tmdbID: 949, slug: "heat", removed: true,
                                          removalPushed: true)])
        await sut.load()

        await sut.toggle(film: heat)

        #expect(sut.lastOutcome?.isFailure == false)
        #expect(sut.lastOutcome?.message.lowercased().contains("removed") == true)
    }

    /// The film is on the watchlist either way — only Letterboxd has not heard. Saying "added to
    /// your Letterboxd watchlist" there would be a straight lie, and saying nothing hides a change
    /// the owner has to know did not leave the house.
    @Test func aChangeTheServerCouldNotCarrySaysItIsWaiting() async {
        let unpushed = WatchlistEntry.locallyAdded(tmdbID: 949, title: "Heat", year: 1995,
                                                   posterPath: nil, position: -1)
        let sut = marks(after: [unpushed], settled: [unpushed], relay: .idle)

        await sut.toggle(film: heat)

        let message = try? #require(sut.lastOutcome?.message)
        #expect(sut.lastOutcome?.isFailure == false)
        #expect(message?.lowercased().contains("added") == true)
        // Names the thing that has not happened yet rather than claiming it has.
        #expect(message?.lowercased().contains("letterboxd hasn't been told") == true)
        #expect(sut.contains(tmdbID: 949))
    }

    @Test func aFailedPushNamesTheFault() async {
        let unpushed = WatchlistEntry.locallyAdded(tmdbID: 949, title: "Heat", year: 1995,
                                                   posterPath: nil, position: -1)
        let sut = marks(after: [unpushed], settled: [unpushed],
                        relay: .init(pushed: 0, failed: 1,
                                     firstError: "Letterboxd is signed out in the server's browser"))

        await sut.toggle(film: heat)

        #expect(sut.lastOutcome?.isFailure == true)
        #expect(sut.lastOutcome?.message == "Letterboxd is signed out in the server's browser")
        // Still on the watchlist locally: the mirror is the truth here, and the push retries.
        #expect(sut.contains(tmdbID: 949))
    }

    /// Two changes to the same film must both be announced. A view watching the id alone would see
    /// no change on the second one and leave the first banner's text on screen.
    ///
    /// Driven by a mirror that really adds and removes, because the second change here is the
    /// opposite of the first and a canned answer cannot be both.
    @Test func aRepeatedChangeIsANewEvent() async {
        let mirror = FakeMirror()
        let sut = WatchlistMarks(entries: { await mirror.entries },
                                 add: { await mirror.add($0) },
                                 remove: { await mirror.remove($0) },
                                 relay: { .init(pushed: 1, failed: 0) })

        await sut.toggle(film: heat)
        let first = sut.lastOutcome
        await sut.toggle(film: heat)
        let second = sut.lastOutcome

        #expect(first?.added == true)
        #expect(second?.added == false)
        #expect(first?.event != second?.event)
        #expect(!sut.contains(tmdbID: 949))
    }

    /// A mirror that behaves like the real one: adds append, removals mark, and the push is taken to
    /// have landed — which is what the syncer records once the relay succeeds.
    private actor FakeMirror {
        var entries: [WatchlistEntry] = []

        func add(_ film: WatchlistFilm) -> [WatchlistEntry] {
            var entry = WatchlistEntry.locallyAdded(tmdbID: film.tmdbID, title: film.title,
                                                    year: film.year, posterPath: film.posterPath,
                                                    position: -1)
            entry.addPushedAt = Date()
            entries.append(entry)
            return entries
        }

        func remove(_ slug: String) -> [WatchlistEntry] {
            guard let index = entries.firstIndex(where: { $0.slug == slug }) else { return entries }
            entries[index].removedAt = Date()
            entries[index].removalPushedAt = Date()
            return entries
        }
    }

    /// The placeholder exists for the single render before the shell's real object does. It must be
    /// inert rather than crash or claim membership.
    @Test func thePlaceholderIsInert() async {
        let sut = WatchlistMarks.placeholder
        await sut.load()
        await sut.toggle(film: heat)

        #expect(!sut.contains(tmdbID: 949))
        #expect(sut.lastOutcome == nil)
    }

    /// Added here with no server, then taken straight back: Letterboxd was never told about either
    /// half, so there is no Letterboxd write to report. Saying there was is the same lie as claiming
    /// an add landed when the server is off, in the opposite direction.
    @Test func takingBackAnUnsentAddClaimsNoLetterboxdWrite() async {
        let unsent = WatchlistEntry.locallyAdded(tmdbID: 949, title: "Heat", year: 1995,
                                                 posterPath: nil, position: -1)
        // The store deletes the row outright, which is what `remove` does to an unsent add.
        let sut = marks(mirror: [unsent], after: [], settled: [], relay: .idle)
        await sut.load()

        await sut.toggle(film: heat)

        let message = try? #require(sut.lastOutcome?.message)
        #expect(message?.lowercased().contains("removed") == true)
        #expect(message?.contains("Letterboxd") == false)
        #expect(sut.lastOutcome?.isFailure == false)
    }

    /// Removed here while the server was off, then put back before the removal ever went out. The
    /// film never left the Letterboxd watchlist, so nothing was written and nothing should be
    /// claimed.
    @Test func reAddingOverAnUnsentRemovalClaimsNoLetterboxdWrite() async {
        let unsentRemoval = crawled(tmdbID: 949, slug: "heat", removed: true)
        let restored = crawled(tmdbID: 949, slug: "heat")
        let sut = marks(mirror: [unsentRemoval], after: [restored], settled: [restored], relay: .idle)
        await sut.load()

        await sut.toggle(film: heat)

        let message = try? #require(sut.lastOutcome?.message)
        #expect(message?.lowercased().contains("added") == true)
        #expect(message?.contains("Letterboxd") == false)
        #expect(sut.contains(tmdbID: 949))
    }
}
