import CoreGraphics
import Testing
@testable import Seret

@Suite struct HeroFlightGeometryTests {
    // MARK: - Backdrop band

    @Test func theBackdropIsTheHeroBand() {
        let frame = HeroFlightGeometry.backdropFrame(window: CGSize(width: 1200, height: 800))
        #expect(frame == CGRect(x: 0, y: 0, width: 1200, height: 444))   // 1200 × 0.37, clamped
    }

    // MARK: - Plan

    private let window = CGSize(width: 1440, height: 900)
    private let target = CGRect(x: 0, y: 0, width: 1440, height: 533)

    @Test func aVisibleSourceFlies() {
        let source = CGRect(x: 100, y: 200, width: 150, height: 225)
        let plan = HeroFlightGeometry.plan(source: source, target: target, window: window, reduceMotion: false)
        #expect(plan == .fly(from: source, to: target))
    }

    @Test func reduceMotionCrossFades() {
        let source = CGRect(x: 100, y: 200, width: 150, height: 225)
        let plan = HeroFlightGeometry.plan(source: source, target: target, window: window, reduceMotion: true)
        #expect(plan == .crossFade)
    }

    @Test func noSourceCrossFades() {
        let plan = HeroFlightGeometry.plan(source: nil, target: target, window: window, reduceMotion: false)
        #expect(plan == .crossFade)
    }

    @Test func anEmptySourceCrossFades() {
        let source = CGRect(x: 100, y: 200, width: 0, height: 225)
        let plan = HeroFlightGeometry.plan(source: source, target: target, window: window, reduceMotion: false)
        #expect(plan == .crossFade)
    }

    @Test func aSourceMostlyAboveTheWindowCrossFades() {
        // y −150 of a 225-tall source: only 75 pt (⅓) sits inside the window — under 50 %.
        let source = CGRect(x: 100, y: -150, width: 150, height: 225)
        let plan = HeroFlightGeometry.plan(source: source, target: target, window: window, reduceMotion: false)
        #expect(plan == .crossFade)
    }

    // MARK: - Frame interpolation

    @Test func framesInterpolate() {
        let from = CGRect(x: 100, y: 200, width: 150, height: 225)
        let to = CGRect(x: 0, y: 0, width: 1440, height: 533)
        #expect(HeroFlightGeometry.frame(from: from, to: to, progress: 0) == from)
        #expect(HeroFlightGeometry.frame(from: from, to: to, progress: 1) == to)
        let mid = HeroFlightGeometry.frame(from: from, to: to, progress: 0.5)
        #expect(mid == CGRect(x: 50, y: 100, width: 795, height: 379))
    }

    @Test func overshootIsAllowed() {
        let from = CGRect(x: 0, y: 0, width: 100, height: 100)
        let to = CGRect(x: 0, y: 0, width: 200, height: 200)
        let overshot = HeroFlightGeometry.frame(from: from, to: to, progress: 1.05)
        #expect(overshot.width > to.width)   // past `to`, not clamped to it
    }

    // MARK: - Corner radius

    @Test func theCornerGoesFrom12To0AndNeverBelow() {
        #expect(HeroFlightGeometry.cornerRadius(progress: 0) == 12)
        #expect(HeroFlightGeometry.cornerRadius(progress: 1) == 0)
        #expect(HeroFlightGeometry.cornerRadius(progress: 0.5) == 6)
        #expect(HeroFlightGeometry.cornerRadius(progress: 1.05) == 0)   // overshoot never goes negative
    }

    // MARK: - Opacity

    @Test func posterAndBackdropOpacitiesAlwaysSumToOne() {
        for step in stride(from: 0.0, through: 1.0, by: 0.05) {
            let sum = HeroFlightGeometry.posterOpacity(progress: step) + HeroFlightGeometry.backdropOpacity(progress: step)
            #expect(abs(sum - 1) < 0.0001)
        }
    }

    @Test func thePosterHoldsThenFades() {
        #expect(HeroFlightGeometry.posterOpacity(progress: 0) == 1)
        #expect(HeroFlightGeometry.posterOpacity(progress: 0.1) == 1)     // still holding before 0.18
        #expect(HeroFlightGeometry.posterOpacity(progress: 0.18) == 1)
        #expect(HeroFlightGeometry.posterOpacity(progress: 0.55) > 0)
        #expect(HeroFlightGeometry.posterOpacity(progress: 0.55) < 1)     // mid-fade
        #expect(HeroFlightGeometry.posterOpacity(progress: 0.92) == 0)
        #expect(HeroFlightGeometry.posterOpacity(progress: 1) == 0)
    }
}
