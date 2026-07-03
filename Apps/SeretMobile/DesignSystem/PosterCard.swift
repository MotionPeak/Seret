import SwiftUI

/// 2:3 poster + title. Presentation-only; pass a resolved poster URL.
/// `width: nil` fills the container (grid cells); a value fixes it (horizontal rails).
struct PosterCard: View {
    let title: String
    let posterURL: URL?
    var width: CGFloat? = 110

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Color.clear
                .aspectRatio(2.0 / 3.0, contentMode: .fit)
                .overlay { RemoteImage(url: posterURL) }
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .stroke(Theme.Palette.hairline, lineWidth: 1))
                .shadow(color: .black.opacity(0.5), radius: 8, y: 4)
            Text(title).font(Theme.Typo.caption())
                .foregroundStyle(Theme.Palette.textSecondary).lineLimit(1)
        }
        .frame(width: width)
    }
}
