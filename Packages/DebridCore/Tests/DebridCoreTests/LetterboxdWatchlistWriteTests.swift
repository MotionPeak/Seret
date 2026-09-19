import Testing
import Foundation
@testable import DebridCore

/// The watchlist change shares the outbox with the diary write, so it shares `LetterboxdWrite`.
/// These cover the discriminator and the body, and — the part that matters for a queue that
/// already has rows on disk — that a write queued before any of this existed still decodes.
@Suite struct LetterboxdWatchlistWriteTests {

    @Test func aWatchlistRemovalCarriesItsOperationAndFlag() {
        let write = LetterboxdWrite(tmdbID: 73, operation: .watchlist, inWatchlist: false)
        #expect(write.operation == .watchlist)
        #expect(write.inWatchlist == false)
        #expect(write.rating == nil)
    }

    @Test func aWriteIsADiaryEntryUnlessItSaysOtherwise() {
        #expect(LetterboxdWrite(tmdbID: 73, rating: 8).operation == .diary)
    }

    /// A row queued before `operation` existed has no such key. It must come back as the diary
    /// write it was, not fail to decode and wedge the whole queue.
    @Test func aRowQueuedBeforeOperationExistedStillDecodes() throws {
        let legacy = """
        {"id":"\(UUID().uuidString)","tmdbID":73,"rating":8,"rewatch":false,"attempts":0}
        """
        let write = try JSONDecoder().decode(LetterboxdWrite.self, from: Data(legacy.utf8))
        #expect(write.operation == .diary)
        #expect(write.inWatchlist == nil)
        #expect(write.rating == 8)
    }

    /// An operation this build does not know about must not wedge the queue either — the same
    /// reasoning as every other field here, applied to the discriminator itself.
    @Test func anUnknownOperationDecodesAsADiaryEntry() throws {
        let future = """
        {"id":"\(UUID().uuidString)","tmdbID":73,"operation":"somethingNew","rewatch":false}
        """
        let write = try JSONDecoder().decode(LetterboxdWrite.self, from: Data(future.utf8))
        #expect(write.operation == .diary)
    }

    @Test func aWatchlistWriteSurvivesARoundTrip() throws {
        let write = LetterboxdWrite(tmdbID: 73, operation: .watchlist, inWatchlist: false)
        let data = try JSONEncoder().encode(write)
        let back = try JSONDecoder().decode(LetterboxdWrite.self, from: data)
        #expect(back.operation == .watchlist)
        #expect(back.inWatchlist == false)
    }

    /// The property is `inWatchlist`, NOT `isInWatchlist`.
    ///
    /// Measured against the live API on 2026-09-19: `isInWatchlist` — which is what the site's own
    /// component calls its state — comes back
    /// `400 {"error":true,"message":"Unknown property at: isInWatchlist"}`. `inWatchlist` returns
    /// 200 and the watchlist page reflects it. The site maps one to the other on the way out.
    @Test func theBodyUsesTheWirePropertyName() throws {
        let json = LetterboxdWatchlistEntry.json(for:
            LetterboxdWrite(tmdbID: 73, operation: .watchlist, inWatchlist: false))
        #expect(json == #"{"inWatchlist":false}"#)
    }

    @Test func theBodyCanAlsoAdd() throws {
        let json = LetterboxdWatchlistEntry.json(for:
            LetterboxdWrite(tmdbID: 73, operation: .watchlist, inWatchlist: true))
        #expect(json == #"{"inWatchlist":true}"#)
    }

    /// Absent means "no change asked for", which is not something to send.
    @Test func aWriteWithNoFlagHasNoBody() {
        #expect(LetterboxdWatchlistEntry.json(for: LetterboxdWrite(tmdbID: 73,
                                                                   operation: .watchlist)) == nil)
    }
}
