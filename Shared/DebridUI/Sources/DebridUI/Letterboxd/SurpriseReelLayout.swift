import CoreGraphics

/// The Surprise Me reel's Cover Flow geometry, shared by the Mac and the Apple TV so the two reels
/// are one design: big cards that always fit — they scale with the window so the whole visible flow
/// (the centre card and three either side) stays inside it — a wide gap at the middle, side cards
/// stacked tighter and turned toward the centre.
///
/// `r` throughout is a card's distance from the middle in cards, fractional while the reel moves.
public enum SurpriseReelLayout {
    public static func cardSize(windowWidth: CGFloat, windowHeight: CGFloat) -> CGSize {
        let width = min(280, max(170, windowWidth * 0.19), max(170, windowHeight * 0.3))
        return CGSize(width: width, height: width * 1.5)
    }

    /// The reel's height as a multiple of a card's: the card, the winner's lift, and the mirror
    /// fading out beneath it.
    public static let reelHeightFactor: CGFloat = 1.36

    /// Horizontal centre of a card `r` places from the middle: the centre gap is wide, the side
    /// cards stack tighter, as in Cover Flow.
    public static func x(r: Double, cardWidth: CGFloat) -> CGFloat {
        let centreGap = cardWidth * 0.82, sideStep = cardWidth * 0.36
        let a = abs(r)
        let distance = a <= 1 ? a * centreGap : centreGap + (a - 1) * sideStep
        return CGFloat(r < 0 ? -distance : distance)
    }

    /// The turn toward the middle: ±50° beyond the first neighbour, 0 at the centre.
    public static func angle(r: Double) -> Double { max(-1, min(1, r)) * -50 }

    public static func scale(r: Double) -> CGFloat {
        let a = abs(r)
        return CGFloat(1 - 0.14 * min(a, 1) - 0.03 * max(0, a - 1))
    }

    /// Fully visible to three places out, gone by four.
    public static func opacity(r: Double) -> Double {
        let a = abs(r)
        return a <= 3 ? 1 : max(0, 1 - (a - 3))
    }

    /// The cards worth drawing with the reel at `position`: five either side of the middle, which
    /// covers everything still visible while it moves. Every drawn card is two posters (it and its
    /// mirror), so drawing the whole ~34-card reel would be wasted decoding.
    public static func visibleIndices(position: Double, count: Int) -> [Int] {
        guard count > 0 else { return [] }
        let centre = Int(position.rounded())
        let lower = max(0, centre - 5), upper = min(count - 1, centre + 5)
        guard lower <= upper else { return [] }
        return Array(lower...upper)
    }
}
