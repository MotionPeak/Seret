import Testing
import Foundation
import UIKit
@testable import Seret

/// The branch whose absence was the permanent spinner.
///
/// `RemoteImage.load` ends in one of three states: it has an image, it knows there is none, or it
/// was cancelled. The third used to write nothing at all — so the tile kept a `ProgressView` with
/// no load behind it, and `.task(id:)` never fired again because a mounted cell neither changes its
/// id nor re-appears. Measured on the real library, a cold launch of Home ends 8 of 58 poster loads
/// cancelled.
@Suite struct RemoteImageResolutionTests {

    /// A fetch that genuinely failed is not a cancellation: the tile should settle on the muted
    /// glyph rather than retry a url that is not going to resolve.
    @Test func aRealFailureSettles() {
        #expect(RemoteImageLoad.resolve(cancelled: false, stillWanted: true, attempt: 0) == .settle)
    }

    /// THE REGRESSION. Interrupted, and the tile is still showing this poster — so nothing is
    /// loading for it any more and nothing ever will unless a new task is started.
    @Test func anInterruptedLoadTheTileStillWantsGoesAgain() {
        #expect(RemoteImageLoad.resolve(cancelled: true, stillWanted: true, attempt: 0) == .retry)
        #expect(RemoteImageLoad.resolve(cancelled: true, stillWanted: true, attempt: 1) == .retry)
    }

    /// Bounded: a url cancelled over and over must end somewhere, and a settled glyph is at least
    /// honest about not loading.
    @Test func retriesRunOut() {
        #expect(RemoteImageLoad.resolve(cancelled: true, stillWanted: true,
                                        attempt: RemoteImageLoad.maxRetries) == .settle)
        #expect(RemoteImageLoad.resolve(cancelled: true, stillWanted: true,
                                        attempt: RemoteImageLoad.maxRetries + 5) == .settle)
    }

    /// A cell recycled onto a different poster must NOT bump the counter. Bumping it would change
    /// the `.task` id that the NEW url's load is running under — cancelling and restarting a load
    /// that had only just begun, once per url change, the whole way down a scrolling grid. It is
    /// also what a `LazyVGrid` cell discarded outside the render window looks like: cancelled,
    /// nothing to show, and nothing worth doing about it, because a re-materialised cell starts a
    /// fresh load of its own.
    @Test func aCellThatMovedOnLeavesTheNewLoadAlone() {
        #expect(RemoteImageLoad.resolve(cancelled: true, stillWanted: false, attempt: 0) == .ignore)
    }

    /// The id has to change with the attempt, or bumping the counter starts no new task at all.
    @Test func theTaskIdChangesWithTheAttempt() {
        let url = URL(string: "https://example.invalid/a.jpg")!
        #expect(RemoteImageLoad.Key(url: url, attempt: 0) != RemoteImageLoad.Key(url: url, attempt: 1))
        #expect(RemoteImageLoad.Key(url: url, attempt: 0) == RemoteImageLoad.Key(url: url, attempt: 0))
    }
}

/// Two tiles asking for the SAME url was recorded as a second, independent cause of the permanent
/// spinner — the loser supposedly waiting out its budget on a poster the winner had already cached.
/// It is not: measured three ways (here, and on the device with sixty tiles over six posters, with
/// distinct ids and with colliding ones), every duplicate resolves. These pin that, so the theory
/// is not re-derived from reading `claimInFlight` and `awaitCached` and guessing.
@Suite(.serialized) struct RemoteImageDuplicateURLTests {

    private static let pngData: Data = {
        let r = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2))
        return r.image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }.pngData()!
    }()

    private func freshURL() -> URL {
        URL(string: "https://example.invalid/\(UUID().uuidString).jpg")!
    }

    /// The ordinary case: the loser reuses the winner's decoded bitmap rather than fetching again.
    /// Identity, not just non-nil — a refetch would decode a second `UIImage`.
    @Test func aSecondViewerReusesTheWinnersBitmap() async {
        let url = freshURL()
        defer { ImageMemoryCache.shared.removeObject(forKey: url as NSURL) }
        let png = Self.pngData

        async let winner: UIImage? = ImageMemoryCache.load(url) { _ in
            try await Task.sleep(for: .milliseconds(100))
            return png
        }
        try? await Task.sleep(for: .milliseconds(20))       // let the winner take the claim
        async let loser: UIImage? = ImageMemoryCache.load(url, waitAttempts: 40) { _ in
            Issue.record("the loser refetched instead of waiting for a claim it could see")
            return png
        }

        let (a, b) = await (winner, loser)
        #expect(a != nil)
        #expect(a === b, "the second tile should get the very bitmap the first one cached")
    }

    /// The worst case: the winner outlasts the loser's whole wait budget. The loser must still end
    /// up with a picture — by fetching it itself, which is the deliberate trade in `load`.
    @Test func aSecondViewerIsNotStrandedWhenTheWinnerOutlastsItsWait() async {
        let url = freshURL()
        defer { ImageMemoryCache.shared.removeObject(forKey: url as NSURL) }
        let png = Self.pngData

        async let winner: UIImage? = ImageMemoryCache.load(url) { _ in
            try await Task.sleep(for: .milliseconds(600))
            return png
        }
        try? await Task.sleep(for: .milliseconds(80))
        // 2 × 50ms of patience against a 600ms winner.
        async let loser: UIImage? = ImageMemoryCache.load(url, waitAttempts: 2) { _ in png }

        let (a, b) = await (winner, loser)
        #expect(a != nil)
        #expect(b != nil, "a tile sharing a url must never be left on its placeholder")
    }

    /// What `RemoteImage` has to work with: a cancelled load is indistinguishable from a failure —
    /// both are nil — which is why the view needs `Task.isCancelled` to tell them apart.
    @Test func aCancelledLoadIsIndistinguishableFromAFailure() async {
        let url = freshURL()
        let png = Self.pngData

        let t = Task {
            await ImageMemoryCache.load(url) { _ in
                try await Task.sleep(for: .seconds(5))
                return png
            }
        }
        try? await Task.sleep(for: .milliseconds(120))
        t.cancel()

        #expect(await t.value == nil)
        #expect(ImageMemoryCache.shared.object(forKey: url as NSURL) == nil,
                "a cancelled load caches nothing, so there is no hit for a later pass to find")
    }

    /// ...and it must not leave its claim held, or the next tile to want that url inherits a dead
    /// one. (This holds today; pinned because the retry now makes a second pass routine.)
    @Test func aCancelledLoadReleasesItsClaim() async {
        let url = freshURL()
        let png = Self.pngData

        let t = Task {
            await ImageMemoryCache.load(url) { _ in
                try await Task.sleep(for: .seconds(5))
                return png
            }
        }
        try? await Task.sleep(for: .milliseconds(120))
        t.cancel()
        _ = await t.value

        let free = ImageMemoryCache.claimInFlight(url)
        if free { ImageMemoryCache.releaseInFlight(url) }
        #expect(free, "the claim should be free for the retry to take")
    }
}
