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

    @Test func midwayBothWaysAreOffered() {
        #expect(RailPager.canPage(offset: 1500, viewport: 1000, content: 4000, .forward))
        #expect(RailPager.canPage(offset: 1500, viewport: 1000, content: 4000, .back))
    }

    /// Measured in the running app: a rail with a 274 pt leading and 28 pt trailing content
    /// margin reports `contentOffset.x == -274` at rest, and `scrollTo(x: 300)` lands at 26.
    @Test func geometryIsMeasuredFromTheStartOfTheScrollableRange() {
        let atRest = RailGeometry(contentOffset: -274, leadingInset: 274, trailingInset: 28,
                                  contentSize: 2042, containerSize: 1138)
        #expect(atRest.offset == 0)
        #expect(atRest.content == 2344)
        #expect(!RailPager.canPage(offset: atRest.offset, viewport: atRest.viewport, content: atRest.content, .back))

        // The true end is contentSize + trailing inset - container = 932 raw.
        let atEnd = RailGeometry(contentOffset: 932, leadingInset: 274, trailingInset: 28,
                                 contentSize: 2042, containerSize: 1138)
        #expect(RailPager.target(offset: 0, viewport: 1138, content: atEnd.content, .forward) == 1138 * 0.85)
        #expect(RailPager.target(offset: 1000, viewport: 1138, content: atEnd.content, .forward) == atEnd.offset)
        #expect(!RailPager.canPage(offset: atEnd.offset, viewport: atEnd.viewport, content: atEnd.content, .forward))
        #expect(RailPager.canPage(offset: atEnd.offset, viewport: atEnd.viewport, content: atEnd.content, .back))
    }

    @Test func canPageBackUntilOnePointFromTheStart() {
        #expect(RailPager.canPage(offset: 850, viewport: 1000, content: 4000, .back))
        #expect(!RailPager.canPage(offset: 0, viewport: 1000, content: 4000, .back))
    }
}
