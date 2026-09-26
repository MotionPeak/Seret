import SwiftUI

/// The Seret play triangle (matches the app icon).
struct PlayTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width, h = rect.height
        path.move(to: CGPoint(x: rect.minX + w * 0.32, y: rect.minY + h * 0.24))
        path.addLine(to: CGPoint(x: rect.minX + w * 0.32, y: rect.minY + h * 0.76))
        path.addLine(to: CGPoint(x: rect.minX + w * 0.78, y: rect.minY + h * 0.50))
        path.closeSubpath()
        return path
    }
}

/// The gold play-triangle logo, with rounded corners and an optional halo. Size it with `.frame`.
struct SeretMark: View {
    var glow: Bool = true

    var body: some View {
        GeometryReader { geo in
            let corner = geo.size.width * 0.14
            PlayTriangle()
                .fill(Theme.Palette.markGradient)
                .overlay(PlayTriangle().stroke(Theme.Palette.markGradient,
                                               style: StrokeStyle(lineWidth: corner, lineJoin: .round)))
                .goldGlow(glow ? geo.size.width * 0.22 : 0, opacity: glow ? 0.55 : 0)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
