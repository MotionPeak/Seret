import CoreGraphics
import SwiftUI
import Testing
@testable import Seret

@Suite struct PosterTiltTests {
    private let size = CGSize(width: 150, height: 225)

    @Test func theCentreIsFlat() {
        let tilt = PosterTilt(location: CGPoint(x: 75, y: 112.5), in: size)
        #expect(tilt.pitch == 0)
        #expect(tilt.yaw == 0)
        #expect(tilt.glare == UnitPoint(x: 0.5, y: 0.5))
    }

    @Test func theTopRightCornerTiltsFully() {
        let tilt = PosterTilt(location: CGPoint(x: 150, y: 0), in: size)
        #expect(tilt.pitch == 8)
        #expect(tilt.yaw == 9)
    }

    @Test func outsideThePosterIsClamped() {
        let farBeyond = PosterTilt(location: CGPoint(x: 900, y: -400), in: size)
        let corner = PosterTilt(location: CGPoint(x: 150, y: 0), in: size)
        #expect(farBeyond == corner)

        let farBottomLeft = PosterTilt(location: CGPoint(x: -900, y: 900), in: size)
        #expect(farBottomLeft.pitch == -8)
        #expect(farBottomLeft.yaw == -9)
    }

    @Test func aZeroSizedPosterIsFlat() {
        #expect(PosterTilt(location: CGPoint(x: 10, y: 10), in: .zero) == .flat)
    }

    @Test func theGlareFollowsThePointer() {
        let tilt = PosterTilt(location: CGPoint(x: 150, y: 0), in: size)
        #expect(tilt.glare == UnitPoint(x: 1, y: 0))
    }
}
