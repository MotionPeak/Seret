import DebridCore
import DebridUI
import SwiftUI

/// The owner's Letterboxd watchlist — films they mean to watch, most recently added first.
struct WatchlistScreen: View {
    @Environment(AppSession.self) private var session
    @State private var model: WatchlistModel?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 40), count: 5)

    var body: some View {
        ZStack {
            CanvasBackground()
            if let model {
                content(model)
            } else {
                Text("Set your Letterboxd username on your iPhone, in Seret → Settings.")
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
        }
        .task {
            if model == nil { model = session.makeWatchlistModel() }
            await model?.syncIfStale()
        }
    }

    @ViewBuilder
    private func content(_ model: WatchlistModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header(model)

                if model.entries.isEmpty {
                    Text("Nothing on your watchlist yet.")
                        .foregroundStyle(Theme.Palette.textSecondary)
                } else {
                    LazyVGrid(columns: columns, spacing: 40) {
                        ForEach(model.entries) { entry in
                            WatchlistTile(entry: entry, owned: model.isOwned(entry))
                        }
                    }
                }
            }
            .padding(.horizontal, 60)
            .padding(.vertical, 40)
            .focusSection()
        }
    }

    @ViewBuilder
    private func header(_ model: WatchlistModel) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 24) {
            Text("Watchlist")
                .font(.largeTitle.bold())
                .foregroundStyle(Theme.Palette.textPrimary)

            Spacer()

            switch model.phase {
            case .idle:
                Button("Sync") { Task { await model.syncNow() } }
                    .buttonStyle(SeretActionButtonStyle())
            case .syncing(let done, let total):
                Text(total > 0 ? "Matching \(done) of \(total)…" : "Reading your watchlist…")
                    .foregroundStyle(Theme.Palette.textSecondary)
            case .failed(let message):
                Text(message).foregroundStyle(.red)
                Button("Retry") { Task { await model.syncNow() } }
                    .buttonStyle(SeretActionButtonStyle())
            }
        }
    }
}

/// One watchlist film.
///
/// A film that resolved to nothing is still shown — as a plain card, not a link. Hiding it would
/// make the count disagree with Letterboxd and give no way to find out why; making it a link would
/// promise a page that does not exist.
private struct WatchlistTile: View {
    let entry: WatchlistEntry
    let owned: Bool

    private var item: MediaItem? {
        guard let tmdbID = entry.tmdbID else { return nil }
        return MediaItem(id: "movie:tmdb:\(tmdbID)", kind: .movie,
                         title: WatchlistName.stripYear(from: entry.name), year: entry.year,
                         sources: [], seasons: [], tmdbID: tmdbID, posterPath: entry.posterPath)
    }

    var body: some View {
        if let item {
            NavigationLink(value: BrowseDestination.detail(item)) {
                poster(item)
            }
            .buttonStyle(.card)
        } else {
            unmatched
        }
    }

    @ViewBuilder
    private func poster(_ item: MediaItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                RemoteImage(url: TMDBClient.imageURL(path: entry.posterPath, size: "w342"))
                    .aspectRatio(2.0 / 3.0, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                if owned {
                    Text("In your library")
                        .font(.caption2.bold())
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Theme.Palette.gold, in: Capsule())
                        .foregroundStyle(.black)
                        .padding(8)
                }
            }
            Text(item.title)
                .font(.caption)
                .lineLimit(1)
                .foregroundStyle(Theme.Palette.textSecondary)
        }
    }

    private var unmatched: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 10)
                .fill(Theme.Palette.surface1)
                .aspectRatio(2.0 / 3.0, contentMode: .fit)
                .overlay {
                    Text(WatchlistName.stripYear(from: entry.name))
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .padding(8)
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
            // textSecondary, not a third step: the tvOS ramp is deliberately two steps because a
            // dimmer one does not read across a room. See Theme.Palette.
            Text("Couldn’t match this on TMDB")
                .font(.caption2)
                .lineLimit(2)
                .foregroundStyle(Theme.Palette.textSecondary)
        }
    }
}
