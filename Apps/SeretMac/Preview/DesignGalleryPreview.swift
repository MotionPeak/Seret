#if DEBUG
import SwiftUI

/// `-uiPreview design` — every design-system piece on one canvas, to screenshot-verify the look.
struct DesignGalleryPreview: View {
    var body: some View {
        ZStack {
            CanvasBackground()
            VStack(spacing: 36) {
                HStack(spacing: 48) {
                    SeretMark().frame(width: 88)
                    Wordmark(hebrewSize: 52)
                }
                HStack(spacing: 16) {
                    Button { } label: { Label("Resume", systemImage: "play.fill") }.buttonStyle(GoldButtonStyle())
                    Button("Details") { }.buttonStyle(GlassButtonStyle())
                    Button("Disabled") { }.buttonStyle(GoldButtonStyle()).disabled(true)
                }
                HStack(spacing: 16) {
                    ForEach(0..<5, id: \.self) { _ in ShimmerView().frame(width: 120, height: 180) }
                }
                GoldProgressBar(fraction: 0.62).frame(width: 320)
                Text("CONTINUE WATCHING").font(Theme.Typo.label()).tracking(1.5).foregroundStyle(Theme.Palette.gold)
            }
        }
    }
}
#endif
