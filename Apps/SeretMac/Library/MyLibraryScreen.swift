import DebridCore
import DebridUI
import SwiftUI

extension EnvironmentValues {
    /// Harness-only: forces the initial Movies/Shows tab without writing the persisted
    /// `@SceneStorage` selection, so a `-uiPreview libraryshows` run never depends on — or leaves
    /// behind — restored scene state.
    @Entry var previewForcedLibraryKind: MediaKind?
}

/// The `.library` section's root: resolves the store from the environment (the harness injects a
/// fixture store this way) or the live session, and shows the real screen — or a skeleton while
/// neither is available yet (very early in launch, before sign-in resolves).
struct LibraryRoot: View {
    @Environment(LibraryStore.self) private var injected: LibraryStore?
    @Environment(AppSession.self) private var session: AppSession?
    @Environment(\.pageLeadingInset) private var pageLeadingInset

    var body: some View {
        if let store = injected ?? session?.libraryStore {
            MyLibraryScreen(store: store)
        } else {
            ScrollView {
                PosterGrid(items: [MediaItem](), isLoading: true) { (_: MediaItem) in EmptyView() }
                    .padding(.leading, pageLeadingInset)
                    .padding(.trailing, 28)
            }
            .padding(.top, 54)
        }
    }
}

/// My Library: the Movies/Shows switch, the poster grid over the shared `LibraryStore`, its
/// loading/empty/failed states, Refresh, and the poster menu (Play / Open / Mark Watched).
struct MyLibraryScreen: View {
    let store: LibraryStore

    @Environment(AppSession.self) private var session: AppSession?
    @Environment(ShellModel.self) private var shell: ShellModel?
    @Environment(TileWatchMarks.self) private var marks: TileWatchMarks?
    @Environment(WatchlistMarks.self) private var watchlist: WatchlistMarks?
    @Environment(\.pageLeadingInset) private var pageLeadingInset
    @Environment(\.previewForcedLibraryKind) private var previewForcedKind: MediaKind?

    private var performer: PosterActionPerformer {
        PosterActionPerformer(session: session, shell: shell, library: store, marks: marks, watchlist: watchlist)
    }

    @SceneStorage("seret.library.kind") private var storedKindRaw = MediaKind.movie.rawValue
    @State private var kindOverride: MediaKind?

    private var kind: MediaKind { kindOverride ?? MediaKind(rawValue: storedKindRaw) ?? .movie }

    private var kindBinding: Binding<MediaKind> {
        Binding(get: { kind }, set: { newValue in
            kindOverride = nil
            storedKindRaw = newValue.rawValue
        })
    }

    private var items: [MediaItem] { kind == .movie ? store.movies : store.shows }
    private var content: LibraryPageContent { LibraryPageContent.make(state: store.state, items: items, kind: kind) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            switch content {
            case .skeleton:
                ScrollView { grid(isLoading: true) }
            case .grid:
                ScrollView { grid(isLoading: false) }
            case .empty(let title, let detail):
                emptyState(icon: "tray", title: title, detail: detail)
            case .failed(let message):
                emptyState(icon: "exclamationmark.triangle", title: message, detail: nil, showRetry: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { if kindOverride == nil { kindOverride = previewForcedKind } }
        .task(id: store.attempt) { await store.load() }
        .task(id: session?.activeProfileID) { await store.reloadWatchStates() }
        .onChange(of: shell?.playbackEndedCount) { _, _ in Task { await store.reloadWatchStates() } }
        .task(id: "\(kind.rawValue)-\(items.count)") {
            ImageMemoryCache.prefetch(items.prefix(18).compactMap { TMDBClient.imageURL(path: $0.posterPath, size: "w342") })
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("My Library").font(Theme.Typo.titleXL())
                // Only a real grid has a count: "0 films" under the skeleton or a failure reads as an
                // answer before there is one. A blank keeps the header's height steady.
                Text(content == .grid ? countCaption : " ").font(Theme.Typo.caption()).foregroundStyle(Theme.Palette.textSecondary)
            }
            Spacer()
            Picker("", selection: kindBinding) {
                Text("Movies").tag(MediaKind.movie)
                Text("Shows").tag(MediaKind.show)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 200)
            Button { store.reload() } label: {
                Image(systemName: "arrow.clockwise").font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.plain)
            .frame(width: 30, height: 30)
            .glassEffect(.regular.interactive(), in: Circle())
            .help("Refresh (\u{2318}R)")
        }
        .padding(.leading, pageLeadingInset)
        .padding(.top, 54)
        .padding(.trailing, 28)
    }

    private var countCaption: String {
        "\(items.count) \(kind == .movie ? "films" : "shows")"
    }

    private func grid(isLoading: Bool) -> some View {
        PosterGrid(items: items, isLoading: isLoading) { item in
            let model = PosterTileModel.library(item)
            let watched = store.watchState(for: item)?.finished ?? false
            let onWatchlist = model.watchlistFilm.map { watchlist?.contains(tmdbID: $0.tmdbID) ?? false } ?? false
            PosterTile(model: model,
                      state: PosterTileState(badge: WatchBadge(store.watchState(for: item))),
                      actions: .make(kind: item.kind, owned: true, watched: watched, onWatchlist: onWatchlist),
                      perform: performer.perform)
        }
        .padding(.leading, pageLeadingInset)
        .padding(.trailing, 28)
        .padding(.bottom, 40)
    }

    private func emptyState(icon: String, title: String, detail: String?, showRetry: Bool = false) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 42, weight: .regular)).foregroundStyle(Theme.Palette.gold)
            Text(title).font(Theme.Typo.headline()).foregroundStyle(Theme.Palette.textPrimary)
                .multilineTextAlignment(.center)
            if let detail {
                Text(detail).font(Theme.Typo.body()).foregroundStyle(Theme.Palette.textSecondary)
                    .multilineTextAlignment(.center)
            }
            if showRetry {
                Button("Try Again") { store.retry() }.buttonStyle(GlassButtonStyle())
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
