import CoreGraphics
import Testing
@testable import Seret

@Suite struct SurpriseReelLayoutTests {
    /// The owner's report: the reel was cut off by the window edges. Everything visible — the
    /// centre card and three either side — must fit inside the window, at any window size.
    @Test(arguments: [(1000.0, 650.0), (1440.0, 900.0), (1728.0, 1080.0), (2560.0, 1440.0)])
    func theVisibleFlowFitsInsideTheWindow(width: Double, height: Double) {
        let card = SurpriseReelLayout.cardSize(windowWidth: CGFloat(width), windowHeight: CGFloat(height))
        // The outermost fully visible card is three places out; its far edge must clear the window.
        let edge = SurpriseReelLayout.x(r: 3, cardWidth: card.width)
            + card.width * SurpriseReelLayout.scale(r: 3) / 2
        #expect(edge * 2 < CGFloat(width))
        // And the reel plus its mirror fits vertically, with room for the copy under it.
        #expect(card.height * 1.36 + 150 + 60 < CGFloat(height))
    }

    @Test func cardsAreBigAtAnOrdinaryWindowSize() {
        let card = SurpriseReelLayout.cardSize(windowWidth: 1440, windowHeight: 900)
        #expect(card.width >= 240)
        #expect(card.height == card.width * 1.5)
    }

    @Test func theFlowIsSymmetricAndCentred() {
        #expect(SurpriseReelLayout.x(r: 0, cardWidth: 200) == 0)
        #expect(SurpriseReelLayout.angle(r: 0) == 0)
        #expect(SurpriseReelLayout.scale(r: 0) == 1)
        for r in [0.5, 1, 2, 3.5] {
            #expect(SurpriseReelLayout.x(r: r, cardWidth: 200) == -SurpriseReelLayout.x(r: -r, cardWidth: 200))
            #expect(SurpriseReelLayout.angle(r: r) == -SurpriseReelLayout.angle(r: -r))
        }
    }

    @Test func sideCardsTurnFullyOnceTheyLeaveTheMiddleAndStackTighter() {
        #expect(abs(SurpriseReelLayout.angle(r: 1)) == 50)
        #expect(abs(SurpriseReelLayout.angle(r: 3)) == 50)
        let firstGap = SurpriseReelLayout.x(r: 1, cardWidth: 200)
        let sideGap = SurpriseReelLayout.x(r: 2, cardWidth: 200) - firstGap
        #expect(sideGap < firstGap)
    }

    @Test func cardsFadeOutBetweenThreeAndFourPlacesOut() {
        #expect(SurpriseReelLayout.opacity(r: 3) == 1)
        #expect(SurpriseReelLayout.opacity(r: 3.5) == 0.5)
        #expect(SurpriseReelLayout.opacity(r: -4) == 0)
    }
}
