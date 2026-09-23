import DebridUI
import SwiftUI
import Testing
@testable import Seret

@Suite struct BrandTests {
    /// The mark is the app icon's triangle; if these points drift the logo stops matching the icon.
    @Test func theMarkMatchesTheIconGeometry() {
        let path = PlayTriangle().path(in: CGRect(x: 0, y: 0, width: 100, height: 100))
        var points: [CGPoint] = []
        path.forEach { element in
            switch element {
            case .move(let point), .line(let point): points.append(point)
            default: break
            }
        }
        let expected = [CGPoint(x: 32, y: 24), CGPoint(x: 32, y: 76), CGPoint(x: 78, y: 50)]
        #expect(points.count == expected.count)
        for (actual, wanted) in zip(points, expected) {
            #expect(abs(actual.x - wanted.x) < 0.001 && abs(actual.y - wanted.y) < 0.001)
        }
    }

    /// The brand colours come from the shared palette, never a local copy that could drift.
    @Test func theGoldIsTheSharedGold() {
        #expect(Theme.Palette.gold == SeretPalette.gold)
        #expect(Theme.Palette.canvas == SeretPalette.canvas)
    }
}
