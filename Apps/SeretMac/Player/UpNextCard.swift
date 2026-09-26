import DebridUI
import SwiftUI

/// A dumb view (so the harness can render it directly) — shown whenever `model.upNextVisible`,
/// whether or not the rest of the HUD is.
struct UpNextCard: View {
    let episodeTitle: String
    let seconds: Int
    let onPlayNow: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("UP NEXT")
                .font(Theme.Typo.label())
                .tracking(1.5)
                .foregroundStyle(Theme.Palette.gold)
            Text(episodeTitle)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.Palette.textPrimary)
            Text("in \(seconds)s")
                .font(.system(size: 12))
                .foregroundStyle(Theme.Palette.textSecondary)
            HStack(spacing: 10) {
                Button("Play Now", action: onPlayNow)
                    .buttonStyle(GoldButtonStyle())
                Button("Dismiss", action: onDismiss)
                    .buttonStyle(GlassButtonStyle())
            }
        }
        .padding(18)
        .frame(width: 320, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
