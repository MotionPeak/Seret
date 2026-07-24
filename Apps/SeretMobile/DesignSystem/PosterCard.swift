import SwiftUI

/// 2:3 poster + title. Presentation-only; pass a resolved poster URL.
/// `width: nil` fills the container (grid cells); a value fixes it (horizontal rails).
/// `watched` dims the poster and shows a ✓ badge (used by the library grid for finished movies).
struct PosterCard: View {
    let title: String
    let posterURL: URL?
    var width: CGFloat? = 110
    var watched: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Color.clear
                .aspectRatio(2.0 / 3.0, contentMode: .fit)
                .overlay { RemoteImage(url: posterURL) }
                .overlay { if watched { Color.black.opacity(0.45) } }   // dim a watched movie
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .stroke(Theme.Palette.hairline, lineWidth: 1))
                .overlay(alignment: .topTrailing) { if watched { watchedBadge } }
                .shadow(color: .black.opacity(0.5), radius: 8, y: 4)
            Text(title).font(Theme.Typo.caption())
                .foregroundStyle(Theme.Palette.textSecondary).lineLimit(1)
        }
        .frame(width: width)
    }

    private var watchedBadge: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 22))
            .foregroundStyle(Theme.Palette.gold)
            .background(Circle().fill(.black.opacity(0.55)))
            .padding(8)
            .accessibilityLabel("Watched")
    }
}
