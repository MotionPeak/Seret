import SwiftUI

/// A centred glass card for a page with nothing to list: an icon, a title, a sentence, an action.
struct GlassMessageCard<Action: View>: View {
    let systemImage: String
    let title: String
    let text: String
    /// Space above the card — a page that centres it vertically passes 0.
    var topPadding: CGFloat = 60
    @ViewBuilder var action: Action
    @Environment(\.horizontalSizeClass) private var hSize

    var body: some View {
        VStack(spacing: Theme.Space.md) {
            Image(systemName: systemImage)
                .font(.system(size: 40, weight: .regular))
                .foregroundStyle(Theme.Palette.textSecondary)
            Text(title)
                .font(Theme.Typo.title())
                .foregroundStyle(Theme.Palette.textPrimary)
                .multilineTextAlignment(.center)
            Text(text)
                .font(Theme.Typo.body())
                .foregroundStyle(Theme.Palette.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            action.padding(.top, Theme.Space.sm)
        }
        .padding(Theme.Space.xxl)
        .frame(maxWidth: 440)
        .seretGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous), interactive: false)
        .padding(.horizontal, PosterTileMetrics.margin(hSize))
        .padding(.top, topPadding)
        .frame(maxWidth: .infinity)
    }
}
