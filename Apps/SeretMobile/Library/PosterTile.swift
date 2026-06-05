import DebridCore
import SwiftUI

/// One tappable poster in the grid — the poster image with the title as plain text below
/// (monochrome, poster-forward, mirroring the tvOS card minus the focus engine). Tapping
/// pushes the item via the enclosing `navigationDestination(for: MediaItem.self)`.
struct PosterTile: View {
    let item: MediaItem

    var body: some View {
        NavigationLink(value: item) {
            VStack(alignment: .leading, spacing: 6) {
                poster
                Text(item.title)
                    .font(.caption).fontWeight(.medium)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var poster: some View {
        Group {
            if let url = TMDBClient.imageURL(path: item.posterPath, size: "w500") {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    ZStack { Rectangle().fill(.gray.opacity(0.18)); ProgressView() }
                }
            } else {
                Rectangle().fill(.gray.opacity(0.3))
                    .overlay { Text(item.title).font(.caption).multilineTextAlignment(.center).padding(6) }
            }
        }
        .aspectRatio(2.0 / 3.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
