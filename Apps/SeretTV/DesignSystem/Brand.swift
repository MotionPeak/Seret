import SwiftUI

/// The Seret play triangle with rounded corners (matches the app icon + iPhone/iPad).
struct PlayTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        p.move(to: CGPoint(x: w * 0.32, y: h * 0.24))
        p.addLine(to: CGPoint(x: w * 0.32, y: h * 0.76))
        p.addLine(to: CGPoint(x: w * 0.78, y: h * 0.50))
        p.closeSubpath()
        return p
    }
}

/// Gold play-triangle logo. Size via `.frame`.
struct SeretMark: View {
    var glow: Bool = true
    var body: some View {
        GeometryReader { geo in
            let corner = geo.size.width * 0.14
            PlayTriangle()
                .fill(Theme.Palette.markGradient)
                .overlay(
                    PlayTriangle().stroke(Theme.Palette.markGradient,
                                          style: StrokeStyle(lineWidth: corner, lineJoin: .round))
                )
                .shadow(color: glow ? Theme.Palette.goldGlow : .clear, radius: glow ? geo.size.width * 0.22 : 0)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// Brand lockup: Hebrew nikud hero + Latin subtitle. Used on the Splash & Sign-in.
struct Wordmark: View {
    var hebrewSize: CGFloat = 90
    var body: some View {
        VStack(spacing: 12) {
            Text("סֶרֶט")
                .font(.system(size: hebrewSize, weight: .bold))
                .foregroundStyle(Theme.Palette.gold)
                .environment(\.layoutDirection, .rightToLeft)
                .shadow(color: Theme.Palette.goldGlow, radius: hebrewSize * 0.4)
            Text("SERET")
                .font(.system(size: hebrewSize * 0.3, weight: .semibold))
                .tracking(hebrewSize * 0.14)
                .foregroundStyle(Theme.Palette.textSecondary)
        }
    }
}
