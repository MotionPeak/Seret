import SwiftUI

/// Thin gold progress line on a faint track.
struct GoldProgressBar: View {
    let fraction: Double
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.18))
                Capsule().fill(Theme.Palette.gold)
                    .frame(width: max(0, min(1, fraction)) * g.size.width)
                    .goldGlow(6, opacity: 0.7)
            }
        }
        .frame(height: 3)
    }
}
