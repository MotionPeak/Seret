import SwiftUI

/// 2:3 poster + title. Presentation-only; pass a resolved poster URL.
struct PosterCard: View {
    let title: String
    let posterURL: URL?
    var width: CGFloat = 110
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AsyncImage(url: posterURL) { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFill()
                } else {
                    ZStack { Theme.Palette.surface2
                        Image(systemName: "film").foregroundStyle(Theme.Palette.textTertiary) }
                }
            }
            .frame(width: width, height: width * 3 / 2)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .stroke(Theme.Palette.hairline, lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 8, y: 4)
            Text(title).font(Theme.Typo.caption())
                .foregroundStyle(Theme.Palette.textSecondary).lineLimit(1)
                .frame(width: width, alignment: .leading)
        }
    }
}
