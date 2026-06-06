import SwiftUI

/// The Seret play triangle with rounded corners (matches the app icon).
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

/// Gold play-triangle logo. `glow` adds the halo; size via `.frame`.
struct SeretMark: View {
    var glow: Bool = true
    var body: some View {
        GeometryReader { geo in
            let corner = geo.size.width * 0.14
            PlayTriangle()
                .fill(Theme.Palette.markGradient)
                .overlay(
                    PlayTriangle()
                        .stroke(Theme.Palette.markGradient,
                                style: StrokeStyle(lineWidth: corner, lineJoin: .round))
                )
                .goldGlow(glow ? geo.size.width * 0.22 : 0, opacity: glow ? 0.55 : 0)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

#Preview {
    ZStack { CanvasBackground(); SeretMark().frame(width: 120) }
}
