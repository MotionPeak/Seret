import Testing
@testable import Seret

@Suite struct PosterGridLayoutTests {
    @Test func anExactFitUsesEveryColumn() {
        #expect(PosterGridLayout(availableWidth: 494).columns == 3)   // 3·150 + 2·22
    }

    @Test func onePointShortDropsAColumn() {
        #expect(PosterGridLayout(availableWidth: 493).columns == 2)
    }

    @Test func aTinyWidthStillHasOneColumn() {
        #expect(PosterGridLayout(availableWidth: 10).columns == 1)
        #expect(PosterGridLayout(availableWidth: -50).columns == 1)
    }

    @Test func theDefaultWindowFitsSix() {
        #expect(PosterGridLayout(availableWidth: 1440 - 274 - 28).columns == 6)
    }

    @Test func skeletonsFillThreeRows() {
        let layout = PosterGridLayout(availableWidth: 1138)
        #expect(layout.skeletonCount() == layout.columns * 3)
    }
}
