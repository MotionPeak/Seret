import Testing
import Foundation
import UIKit
@testable import Seret

/// Guards the "tile spins forever" regression.
///
/// `RemoteImage` used to inline its whole load in a `.task`, where every failure path was a bare
/// `return`. Because `body` renders the placeholder whenever the image is nil — and the tvOS
/// placeholder is an *infinite* `ProgressView` — any failure left the tile spinning for good, with
/// no retry (`.task(id: url)` never re-fires while the url is unchanged).
///
/// The path that actually shipped was a race with `prefetch()`:
///   prefetch claims the url → `RemoteImage` loses the claim → `awaitCached` polls for 2s and gives
///   up → the re-claim `guard` also fails because the prefetch still holds it → `return`.
/// So exactly the images whose prefetch ran longer than the wait budget hung forever, which is why
/// it was always a consistent *minority* of tiles rather than all or none.
///
/// The load now lives in `ImageMemoryCache.load`, which is reachable from a test.
@Suite(.serialized) struct RemoteImageLoadTests {

    /// A real 2x2 PNG, so `UIImage(data:)` actually decodes.
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

    /// THE REGRESSION. Someone else (a prefetch) holds the claim and never publishes. The loader
    /// must still produce an image rather than sitting on the placeholder forever.
    @Test func aClaimThatNeverPublishesStillYieldsAnImage() async {
        let url = freshURL()
        // Stand in for a prefetch that claimed the url and then died without caching anything.
        #expect(ImageMemoryCache.claimInFlight(url))
        defer { ImageMemoryCache.releaseInFlight(url) }

        let image = await ImageMemoryCache.load(url, waitAttempts: 2) { _ in Self.pngData }

        #expect(image != nil, "a dead claim must not strand the tile on its placeholder")
    }

    /// An already-cached image comes back without touching the network.
    @Test func aCachedImageIsReturnedWithoutFetching() async {
        let url = freshURL()
        let cached = UIImage(data: Self.pngData)!
        ImageMemoryCache.shared.setObject(cached, forKey: url as NSURL,
                                          cost: ImageMemoryCache.cost(of: cached))
        defer { ImageMemoryCache.shared.removeObject(forKey: url as NSURL) }

        let image = await ImageMemoryCache.load(url) { _ in Self.pngData }

        // Identity, not just non-nil: a refetch would decode a *new* UIImage.
        #expect(image === cached, "a cache hit must return the cached instance, not refetch")
    }

    /// The happy path also populates the cache, so the next appearance is instant.
    @Test func aFetchedImageIsCached() async {
        let url = freshURL()
        defer { ImageMemoryCache.shared.removeObject(forKey: url as NSURL) }

        let image = await ImageMemoryCache.load(url) { _ in Self.pngData }

        #expect(image != nil)
        #expect(ImageMemoryCache.shared.object(forKey: url as NSURL) != nil)
    }

    /// A genuine failure reports nil — so the view can show a settled "no image" state instead of
    /// spinning. Returning nil is the *point*; it is what lets the caller stop the spinner.
    @Test func aFailedFetchReportsFailureRatherThanHanging() async {
        let url = freshURL()
        struct Boom: Error {}

        let image = await ImageMemoryCache.load(url) { _ in throw Boom() }

        #expect(image == nil)
    }

    /// Undecodable bytes are a failure, not a hang.
    @Test func undecodableBytesReportFailure() async {
        let url = freshURL()

        let image = await ImageMemoryCache.load(url) { _ in Data("not a png".utf8) }

        #expect(image == nil)
    }

    /// The claim must be released whichever way the load ends, or the *next* view to ask for the
    /// same url inherits a dead claim — which is how one failure used to poison a whole rail.
    @Test func theClaimIsReleasedAfterAFailure() async {
        let url = freshURL()
        struct Boom: Error {}

        _ = await ImageMemoryCache.load(url) { _ in throw Boom() }

        #expect(ImageMemoryCache.claimInFlight(url), "the claim should be free to take again")
        ImageMemoryCache.releaseInFlight(url)
    }
}
