#if DEBUG
import DebridCore
import SwiftUI

/// `-uiPreview posters` / `postersloading` — the fixture films in a `PosterGrid`, so the card,
/// hover, watch badges and loading skeletons can be screenshot-verified without signing in.
struct PosterGalleryPreview: View {
    var isLoading: Bool = false

    var body: some View {
        ZStack {
            CanvasBackground()
            ScrollView {
                PosterGrid(items: Fixture.films, isLoading: isLoading) { item in
                    Button {
                    } label: {
                        PosterCard(title: item.title,
                                  caption: item.year.map(String.init) ?? "",
                                  posterURL: TMDBClient.imageURL(path: item.posterPath, size: "w342"),
                                  badge: WatchBadge(Fixture.watch[WatchKey.content(forMovie: item)]),
                                  highlighted: item.id == Fixture.films[1].id)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 40)
            }
        }
        .frame(minWidth: 1100, minHeight: 700)
    }
}
#endif
