import SwiftUI

/// Brand lockup: Hebrew nikud hero + Latin subtitle. Used on Splash & Sign-in.
struct Wordmark: View {
    var hebrewSize: CGFloat = 44
    var body: some View {
        VStack(spacing: Theme.Space.sm) {
            Text("סֶרֶט")
                .font(.system(size: hebrewSize, weight: .bold))
                .foregroundStyle(Theme.Palette.gold)
                .environment(\.layoutDirection, .rightToLeft)
                .goldGlow(hebrewSize * 0.5, opacity: 0.5)
            Text("SERET")
                .font(.system(size: hebrewSize * 0.32, weight: .semibold))
                .tracking(hebrewSize * 0.14)
                .foregroundStyle(Theme.Palette.textSecondary)
        }
    }
}

#Preview { ZStack { CanvasBackground(); Wordmark() } }
