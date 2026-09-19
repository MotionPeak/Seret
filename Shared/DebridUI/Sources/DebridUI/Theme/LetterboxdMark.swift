import SwiftUI

/// Letterboxd's three dots, drawn rather than bundled.
///
/// The mark is three circles, so an image asset would be a binary to ship, a set of scale factors
/// to maintain and a licensing question, to draw what two lines of SwiftUI draw exactly.
///
/// Lives here rather than in either app because both ratings rows show it, and the palette next
/// door is a standing reminder of what happens when a brand is defined twice.
public struct LetterboxdMark: View {
    private let diameter: CGFloat

    /// - Parameter diameter: one dot. tvOS reads at ten feet, mobile in the hand, so the caller sizes it.
    public init(diameter: CGFloat) { self.diameter = diameter }

    /// Letterboxd's own brand colours, in its own order.
    private static let dots: [Color] = [Color(hex: 0x00E054), Color(hex: 0x40BCF4), Color(hex: 0xFF8000)]

    public var body: some View {
        HStack(spacing: diameter * 0.16) {
            ForEach(Array(Self.dots.enumerated()), id: \.offset) { _, colour in
                Circle().fill(colour).frame(width: diameter, height: diameter)
            }
        }
        .accessibilityHidden(true)   // the score beside it is already labelled
    }
}
