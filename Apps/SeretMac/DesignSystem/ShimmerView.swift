import SwiftUI

/// The loading placeholder for rails and grids: a surface with a soft band sweeping across it.
/// Loading in Seret is always shimmer, never a spinner. Still under Reduce Motion.
struct ShimmerView: View {
    var cornerRadius: CGFloat = Theme.Radius.card
    @State private var phase: CGFloat = -1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Theme.Palette.surface2)
            .overlay(
                GeometryReader { geo in
                    LinearGradient(colors: [.clear, Color.white.opacity(0.08), .clear],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: geo.size.width * 0.6)
                        .offset(x: phase * geo.size.width)
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            )
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) { phase = 1.4 }
            }
    }
}
