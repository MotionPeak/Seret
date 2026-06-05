import DebridCore
import DebridUI
import SwiftUI

/// One focusable poster tile. The poster itself is the `.card` (tvOS focus lift + ring); the title
/// sits *below* the card as plain text — no grey caption box — so the grid reads cleanly.
struct PosterCard: View {
    let item: MediaItem

    private let width: CGFloat = 220
    private let height: CGFloat = 330

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink(value: item) { poster }
                .buttonStyle(.card)
            Text(item.title)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
                .frame(width: width, alignment: .leading)
        }
    }

    @ViewBuilder private var poster: some View {
        if let url = TMDBClient.imageURL(path: item.posterPath, size: "w500") {
            AsyncImage(url: url) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                loading
            }
            .frame(width: width, height: height)
            .clipped()
        } else {
            noPoster.frame(width: width, height: height)
        }
    }

    /// A small spinner while the poster loads — not a flat grey rectangle.
    private var loading: some View {
        ZStack {
            Rectangle().fill(.gray.opacity(0.18))
            ProgressView()
        }
    }

    /// No artwork available — fall back to the title on a muted tile.
    private var noPoster: some View {
        Rectangle()
            .fill(.gray.opacity(0.3))
            .overlay {
                Text(item.title)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .padding(12)
            }
    }
}
