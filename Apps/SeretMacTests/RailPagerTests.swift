import CoreGraphics
import Testing
@testable import Seret

@Suite struct RailPagerTests {
    @Test func pagesByMostOfTheViewport() {
        let target = RailPager.target(offset: 0, viewport: 1000, content: 4000, .forward)
        #expect(target == 850)
    }

    @Test func stopsAtTheEnd() {
        let target = RailPager.target(offset: 2800, viewport: 1000, content: 4000, .forward)
        #expect(target == 3000)
    }

    @Test func neverBeforeTheStart() {
        let target = RailPager.target(offset: 200, viewport: 1000, content: 4000, .back)
        #expect(target == 0)
    }

    @Test func aRailThatFitsCannotPage() {
        #expect(!RailPager.canPage(offset: 0, viewport: 1000, content: 900, .forward))
        #expect(!RailPager.canPage(offset: 0, viewport: 1000, content: 900, .back))
    }

    @Test func canPageForwardUntilOnePointFromTheEnd() {
        #expect(RailPager.canPage(offset: 0, viewport: 1000, content: 4000, .forward))
        #expect(!RailPager.canPage(offset: 3000, viewport: 1000, content: 4000, .forward))
    }

    @Test func canPageBackUntilOnePointFromTheStart() {
        #expect(RailPager.canPage(offset: 850, viewport: 1000, content: 4000, .back))
        #expect(!RailPager.canPage(offset: 0, viewport: 1000, content: 4000, .back))
    }
}
