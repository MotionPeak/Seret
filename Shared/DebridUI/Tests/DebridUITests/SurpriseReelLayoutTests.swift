import CoreGraphics
import DebridUI
import Testing

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
        #expect(card.height * SurpriseReelLayout.reelHeightFactor + 150 + 60 < CGFloat(height))
    }

    /// The Apple TV's screen is a fixed 1920×1080, and its copy under the reel is taller than the
    /// Mac's — focusable buttons are big on a TV. The label, the reel with its mirror and that copy
    /// must still fit inside the title-safe area (60 pt top and bottom).
    @Test func theTVLayoutFitsInsideTheTitleSafeArea() {
        let card = SurpriseReelLayout.cardSize(windowWidth: 1920, windowHeight: 1080)
        let label: CGFloat = 40 + 44, copy: CGFloat = 280
        #expect(label + card.height * SurpriseReelLayout.reelHeightFactor + copy < 1080 - 120)
        let edge = SurpriseReelLayout.x(r: 3, cardWidth: card.width)
            + card.width * SurpriseReelLayout.scale(r: 3) / 2
        #expect(edge * 2 < 1920 - 180)
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

    /// Only the cards near the middle are drawn — the reel is ~34 long and every drawn card is two
    /// posters (it and its mirror).
    @Test func onlyTheCardsAroundTheMiddleAreDrawn() {
        #expect(SurpriseReelLayout.visibleIndices(position: 0, count: 34) == Array(0...5))
        #expect(SurpriseReelLayout.visibleIndices(position: 10.4, count: 34) == Array(5...15))
        #expect(SurpriseReelLayout.visibleIndices(position: 33, count: 34) == Array(28...33))
        #expect(SurpriseReelLayout.visibleIndices(position: 0, count: 0).isEmpty)
    }
}
