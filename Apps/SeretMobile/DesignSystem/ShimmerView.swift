import SwiftUI

/// Animated loading placeholder. Use to fill rails/grids while data loads.
struct ShimmerView: View {
    var cornerRadius: CGFloat = Theme.Radius.card
    @State private var phase: CGFloat = -1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Theme.Palette.surface2)
            .overlay(
                GeometryReader { g in
                    LinearGradient(colors: [.clear, Color.white.opacity(0.08), .clear],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: g.size.width * 0.6)
                        .offset(x: phase * g.size.width)
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            )
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) { phase = 1.4 }
            }
    }
}
