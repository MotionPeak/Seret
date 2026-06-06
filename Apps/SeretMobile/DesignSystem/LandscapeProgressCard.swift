import SwiftUI

/// 16:9 thumbnail + gold progress + title/subtitle. For Continue Watching.
struct LandscapeProgressCard: View {
    let title: String
    let subtitle: String
    let imageURL: URL?
    let fraction: Double
    var width: CGFloat = 168
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AsyncImage(url: imageURL) { phase in
                if case .success(let image) = phase { image.resizable().scaledToFill() }
                else { Theme.Palette.surface2 }
            }
            .frame(width: width, height: width * 9 / 16)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .stroke(Theme.Palette.hairline, lineWidth: 1))
            GoldProgressBar(fraction: fraction).frame(width: width)
            Text(title).font(Theme.Typo.caption())
                .foregroundStyle(Theme.Palette.textPrimary).lineLimit(1).frame(width: width, alignment: .leading)
            if !subtitle.isEmpty {
                Text(subtitle).font(.system(size: 11)).foregroundStyle(Theme.Palette.textTertiary)
                    .lineLimit(1).frame(width: width, alignment: .leading)
            }
        }
    }
}
