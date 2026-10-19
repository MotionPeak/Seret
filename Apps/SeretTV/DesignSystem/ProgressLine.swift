import SwiftUI

/// A thin, rounded resume/progress line: a white fill on a 30% white track. Out-of-range fractions are clamped, so a stale position past the end draws a full line.
struct ProgressLine: View {
    let fraction: Double
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.30))
                Capsule().fill(Theme.Palette.focus)
                    .frame(width: max(0, min(1, fraction)) * g.size.width)
            }
        }
        .frame(height: height)
    }
}
