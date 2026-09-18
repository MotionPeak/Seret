import DebridCore
import DebridUI
import SwiftUI

/// The owner's Letterboxd watchlist — films they mean to watch, most recently added first.
struct WatchlistScreen: View {
    @Environment(AppSession.self) private var session
    @State private var model: WatchlistModel?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    var body: some View {
        ZStack {
            CanvasBackground()
            if let model {
                content(model)
            } else {
                Text("Turn on Letterboxd in Settings and set your username.")
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding()
            }
        }
        .navigationTitle("Watchlist")
        .toolbar {
            if let model {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Sync") { Task { await model.syncNow() } }
                        .disabled(isSyncing(model))
                }
            }
        }
        .task {
            if model == nil { model = session.makeWatchlistModel() }
            await model?.syncIfStale()
        }
    }

    private func isSyncing(_ model: WatchlistModel) -> Bool {
        if case .syncing = model.phase { return true }
        return false
    }

    @ViewBuilder
    private func content(_ model: WatchlistModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                status(model)

                if model.entries.isEmpty {
                    Text("Nothing on your watchlist yet.")
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .padding(.top, Theme.Space.lg)
                } else {
                    LazyVGrid(columns: columns, spacing: Theme.Space.md) {
                        ForEach(model.entries) { entry in
                            WatchlistCard(entry: entry, owned: model.isOwned(entry))
                        }
                    }
                }
            }
            .padding(Theme.Space.md)
        }
        .scrollContentBackground(.hidden)
        // Pull-to-refresh is the sync button by another name.
        .refreshable { await model.syncNow() }
    }

    @ViewBuilder
    private func status(_ model: WatchlistModel) -> some View {
        switch model.phase {
        case .idle:
            EmptyView()
        case .syncing(let done, let total):
            HStack(spacing: 10) {
                ProgressView()
                Text(total > 0 ? "Matching \(done) of \(total)…" : "Reading your watchlist…")
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
        case .failed(let message):
            Text(message).foregroundStyle(.red)
        }
    }
}

/// One watchlist film.
///
/// A film that resolved to nothing is still shown — as a plain card, not a link. Hiding it would
/// make the count disagree with Letterboxd and give no way to find out why; making it a link would
/// promise a page that does not exist.
private struct WatchlistCard: View {
    @Environment(AppRouter.self) private var router
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
            // The mobile app presents a title as a full-screen cover off the router, not a pushed
            // navigation value — that is `BrowseDestination`, which is tvOS's shell.
            Button { router.detail = item } label: { poster(item) }
                .buttonStyle(.plain)
        } else {
            unmatched
        }
    }

    @ViewBuilder
    private func poster(_ item: MediaItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                RemoteImage(url: TMDBClient.imageURL(path: entry.posterPath, size: "w342"))
                    .aspectRatio(2.0 / 3.0, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                if owned {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.Palette.gold)
                        .padding(6)
                        .accessibilityLabel("In your library")
                }
            }
            Text(item.title)
                .font(.caption)
                .lineLimit(1)
                .foregroundStyle(Theme.Palette.textSecondary)
        }
    }

    private var unmatched: some View {
        VStack(alignment: .leading, spacing: 6) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Theme.Palette.surface1)
                .aspectRatio(2.0 / 3.0, contentMode: .fit)
                .overlay {
                    Text(WatchlistName.stripYear(from: entry.name))
                        .font(.caption2)
                        .multilineTextAlignment(.center)
                        .padding(6)
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
            Text("Couldn’t match on TMDB")
                .font(.caption2)
                .lineLimit(2)
                .foregroundStyle(Theme.Palette.textTertiary)
        }
    }
}
