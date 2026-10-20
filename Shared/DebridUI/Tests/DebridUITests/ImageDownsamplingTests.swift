import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import DebridUI

@Suite struct ImageDownsamplingTests {
    /// A real encoded PNG of the given pixel size, so `decode` is exercised end to end.
    private func png(width: Int, height: Int) throws -> Data {
        let ctx = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                         bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(CGColor(red: 0.8, green: 0.2, blue: 0.1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(ctx.makeImage())
        let out = NSMutableData()
        let dest = try #require(CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, nil)
        #expect(CGImageDestinationFinalize(dest))
        return out as Data
    }

    @Test func costIsFourBytesPerPixel() {
        #expect(ImageDownsampling.cost(pixelWidth: 500, pixelHeight: 750) == 1_500_000)
        #expect(ImageDownsampling.cost(pixelWidth: 1280, pixelHeight: 720) == 3_686_400)
        #expect(ImageDownsampling.cost(pixelWidth: -1, pixelHeight: 10) == 0)
    }

    @Test func targetPixelsScaleAndRoundUpToTheBucket() throws {
        // A 150pt headshot at @2x is 300px → 320 (the next multiple of 64).
        let t = try #require(ImageDownsampling.targetPixels(points: CGSize(width: 150, height: 150), scale: 2))
        #expect(t == CGSize(width: 320, height: 320))
        // Frames a point apart share one bucket, so they share one cache entry.
        let a = ImageDownsampling.targetPixels(points: CGSize(width: 240, height: 360), scale: 2)
        let b = ImageDownsampling.targetPixels(points: CGSize(width: 241, height: 361), scale: 2)
        #expect(a == b)
        #expect(ImageDownsampling.targetPixels(points: .zero, scale: 2) == nil)
    }

    @Test func fillCoversBothSidesFitTheTighterOne() {
        let poster = CGSize(width: 500, height: 750)
        // Fill a 320×320 square: the WIDTH must reach 320, so 750 × 0.64 = 480.
        #expect(ImageDownsampling.maxPixelSize(source: poster, target: CGSize(width: 320, height: 320), fit: .fill) == 480)
        // Fit the same square: the HEIGHT bounds it, so the longest side is 320.
        #expect(ImageDownsampling.maxPixelSize(source: poster, target: CGSize(width: 320, height: 320), fit: .fit) == 320)
    }

    @Test func aSourceNoLargerThanTheTargetIsNotDownsampled() {
        let poster = CGSize(width: 500, height: 750)
        #expect(ImageDownsampling.maxPixelSize(source: poster, target: CGSize(width: 512, height: 768), fit: .fill) == nil)
        #expect(ImageDownsampling.maxPixelSize(source: poster, target: CGSize(width: 1024, height: 64), fit: .fill) == nil)
    }

    @Test func decodeLandsAtTheTargetSize() throws {
        // A h632 headshot (421×632) drawn in a 160pt circle at @2x.
        let data = try png(width: 421, height: 632)
        let target = try #require(ImageDownsampling.targetPixels(points: CGSize(width: 160, height: 160), scale: 2))
        let image = try #require(ImageDownsampling.decode(data, target: target, fit: .fill))
        #expect(image.width == 320)
        #expect(image.height == 481)      // rounded UP so the width still covers 320
        let full = ImageDownsampling.cost(pixelWidth: 421, pixelHeight: 632)
        let small = ImageDownsampling.cost(pixelWidth: image.width, pixelHeight: image.height)
        #expect(small * 10 < full * 6)       // ~58% of the full decode
    }

    @Test func decodeWithoutATargetKeepsTheNativeSize() throws {
        let image = try #require(ImageDownsampling.decode(try png(width: 300, height: 169), target: nil))
        #expect(image.width == 300)
        #expect(image.height == 169)
    }

    /// Not downsampled = the plain decode, so a cache can file it under the plain url.
    @Test func decodeSaysWhetherItDownsampled() throws {
        let data = try png(width: 421, height: 632)
        let small = try #require(ImageDownsampling.decodeReporting(
            data, target: CGSize(width: 320, height: 320)))
        #expect(small.downsampled)
        let large = try #require(ImageDownsampling.decodeReporting(
            data, target: CGSize(width: 448, height: 704)))
        #expect(!large.downsampled)
        #expect(large.image.width == 421)
        let plain = try #require(ImageDownsampling.decodeReporting(data, target: nil))
        #expect(!plain.downsampled)
    }

    @Test func decodeRejectsBytesThatAreNotAnImage() {
        #expect(ImageDownsampling.decode(Data("not an image".utf8), target: nil) == nil)
    }

    @Test func eachTargetHasItsOwnCacheKey() throws {
        let url = try #require(URL(string: "https://image.tmdb.org/t/p/w500/abc.jpg"))
        #expect(ImageDownsampling.cacheKey(url, target: nil) == url)
        let small = ImageDownsampling.cacheKey(url, target: CGSize(width: 320, height: 448))
        let large = ImageDownsampling.cacheKey(url, target: CGSize(width: 512, height: 768))
        #expect(small != url)
        #expect(small != large)
        #expect(small == ImageDownsampling.cacheKey(url, target: CGSize(width: 320, height: 448)))
    }

    @Test func theBudgetScalesWithTheDeviceAndIsClamped() {
        let gb: UInt64 = 1024 * 1024 * 1024
        #expect(ImageDownsampling.cacheBudget(physicalMemory: 3 * gb) == 96 * 1024 * 1024)
        #expect(ImageDownsampling.cacheBudget(physicalMemory: 2 * gb) == 64 * 1024 * 1024)
        #expect(ImageDownsampling.cacheBudget(physicalMemory: 1 * gb) == 48 * 1024 * 1024)
        #expect(ImageDownsampling.cacheBudget(physicalMemory: 16 * gb) == 96 * 1024 * 1024)
    }
}
