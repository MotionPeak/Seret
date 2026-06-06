import SwiftUI

/// Branded intro: mark scales in, glow blooms, wordmark rises, gold bar fills.
/// Fixed ~1.6s; Home shows its own shimmer until data lands.
struct SplashView: View {
    var onFinished: () -> Void
    @State private var markIn = false
    @State private var wordIn = false
    @State private var latinIn = false
    @State private var progress: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Theme.Palette.trueBlack.ignoresSafeArea()
            RadialGradient(colors: [Theme.Palette.goldGlow, .clear],
                           center: .center, startRadius: 0, endRadius: 360)
                .opacity(markIn ? 1 : 0).ignoresSafeArea()
            VStack(spacing: Theme.Space.xxl) {
                SeretMark().frame(width: 96)
                    .scaleEffect(markIn ? 1 : 0.6).opacity(markIn ? 1 : 0)
                VStack(spacing: Theme.Space.sm) {
                    Text("סֶרֶט").font(.system(size: 48, weight: .bold))
                        .foregroundStyle(Theme.Palette.gold)
                        .environment(\.layoutDirection, .rightToLeft)
                        .goldGlow(24, opacity: 0.5)
                        .opacity(wordIn ? 1 : 0).offset(y: wordIn ? 0 : 8)
                    Text("SERET").font(.system(size: 15, weight: .semibold)).tracking(6)
                        .foregroundStyle(Theme.Palette.textSecondary).opacity(latinIn ? 1 : 0)
                }
            }
            VStack { Spacer()
                GoldProgressBar(fraction: progress).frame(width: 120).padding(.bottom, 48) }
        }
        .task { await run() }
    }

    private func run() async {
        if reduceMotion {
            markIn = true; wordIn = true; latinIn = true; progress = 1
            try? await Task.sleep(for: .seconds(0.9)); onFinished(); return
        }
        withAnimation(Theme.Motion.hero) { markIn = true }
        try? await Task.sleep(for: .seconds(0.35)); withAnimation(Theme.Motion.standard) { wordIn = true }
        try? await Task.sleep(for: .seconds(0.20)); withAnimation(Theme.Motion.fade) { latinIn = true }
        withAnimation(.easeInOut(duration: 1.05)) { progress = 1 }
        try? await Task.sleep(for: .seconds(1.05)); onFinished()
    }
}
