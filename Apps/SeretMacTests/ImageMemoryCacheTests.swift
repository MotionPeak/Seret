import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Seret

@Suite struct ImageMemoryCacheTests {
    /// A real 12×8 PNG, so decoding is exercised end to end.
    private static func pngData(width: Int = 12, height: Int = 8) -> Data {
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.9, green: 0.7, blue: 0.1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let data = NSMutableData()
        let dest = CGImageDestinationCreateWithData(data as CFMutableData, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
        CGImageDestinationFinalize(dest)
        return data as Data
    }

    /// Every test gets its own URL: the cache is process-wide and tests run in parallel.
    private static func uniqueURL() -> URL { URL(string: "https://images.test/\(UUID().uuidString).png")! }

    private actor Counter {
        private(set) var count = 0
        func bump() { count += 1 }
    }

    @Test func decodesAPNGAtItsPixelSize() throws {
        let image = try #require(ImageMemoryCache.decode(Self.pngData()))
        #expect(image.cgImage.width == 12 && image.cgImage.height == 8)
        #expect(image.cost >= 12 * 8 * 4)
    }

    @Test func garbageDecodesToNothing() {
        #expect(ImageMemoryCache.decode(Data("not an image".utf8)) == nil)
    }

    @Test func aLoadedImageIsServedFromTheCacheAfterwards() async {
        let url = Self.uniqueURL(), counter = Counter(), png = Self.pngData()
        let fetch: @Sendable (URL) async throws -> Data = { _ in await counter.bump(); return png }
        let first = await ImageMemoryCache.load(url, fetch: fetch)
        let second = await ImageMemoryCache.load(url, fetch: fetch)
        #expect(first != nil && second != nil)
        #expect(await counter.count == 1)
    }

    @Test func aFailedFetchYieldsNothing() async {
        struct Offline: Error {}
        let image = await ImageMemoryCache.load(Self.uniqueURL(), fetch: { _ in throw Offline() })
        #expect(image == nil)
    }

    @Test func onlyACancelledLoadThatIsStillWantedRetries() {
        #expect(RemoteImageLoad.resolve(cancelled: false, stillWanted: true, attempt: 0) == .settle)
        #expect(RemoteImageLoad.resolve(cancelled: true, stillWanted: false, attempt: 0) == .ignore)
        #expect(RemoteImageLoad.resolve(cancelled: true, stillWanted: true, attempt: 0) == .retry)
        #expect(RemoteImageLoad.resolve(cancelled: true, stillWanted: true, attempt: 3) == .settle)
    }
}
