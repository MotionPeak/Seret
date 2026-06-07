import SwiftUI

/// Branded intro: the mark scales + glows in, then the wordmark rises. ~1.6s.
struct SplashView: View {
    var onFinished: () -> Void
    @State private var markIn = false
    @State private var wordIn = false
    @State private var latinIn = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            RadialGradient(colors: [Theme.Palette.goldGlow, .clear],
                           center: .center, startRadius: 0, endRadius: 760)
                .opacity(markIn ? 1 : 0).ignoresSafeArea()
            VStack(spacing: 56) {
                SeretMark().frame(width: 200)
                    .scaleEffect(markIn ? 1 : 0.6).opacity(markIn ? 1 : 0)
                VStack(spacing: 16) {
                    Text("סֶרֶט").font(.system(size: 96, weight: .bold))
                        .foregroundStyle(Theme.Palette.gold)
                        .environment(\.layoutDirection, .rightToLeft)
                        .shadow(color: Theme.Palette.goldGlow, radius: 44)
                        .opacity(wordIn ? 1 : 0).offset(y: wordIn ? 0 : 16)
                    Text("SERET").font(.system(size: 30, weight: .semibold)).tracking(12)
                        .foregroundStyle(Theme.Palette.textSecondary).opacity(latinIn ? 1 : 0)
                }
            }
        }
        .task { await run() }
    }

    private func run() async {
        if reduceMotion {
            markIn = true; wordIn = true; latinIn = true
            try? await Task.sleep(for: .seconds(1.0)); onFinished(); return
        }
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) { markIn = true }
        try? await Task.sleep(for: .seconds(0.4)); withAnimation(.spring(response: 0.5)) { wordIn = true }
        try? await Task.sleep(for: .seconds(0.25)); withAnimation(.easeInOut(duration: 0.3)) { latinIn = true }
        try? await Task.sleep(for: .seconds(0.9)); onFinished()
    }
}
