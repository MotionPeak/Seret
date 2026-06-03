import DebridCore
import SwiftUI

/// One focusable poster tile (tvOS `.card` style gives the focus lift + ring).
/// Selecting it pushes the item's Detail screen (see `LibraryShell` navigationDestination).
struct PosterCard: View {
    let item: MediaItem

    var body: some View {
        NavigationLink(value: item) {
            VStack(alignment: .leading, spacing: 10) {
                poster
                Text(item.title)
                    .font(.caption)
                    .lineLimit(1)
                    .frame(width: 220, alignment: .leading)
            }
        }
        .buttonStyle(.card)
    }

    @ViewBuilder private var poster: some View {
        if let url = TMDBClient.imageURL(path: item.posterPath, size: "w500") {
            AsyncImage(url: url) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                placeholder
            }
            .frame(width: 220, height: 330)
            .clipped()
        } else {
            placeholder.frame(width: 220, height: 330)
        }
    }

    private var placeholder: some View {
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
