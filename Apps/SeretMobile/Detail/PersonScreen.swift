import DebridCore
import DebridUI
import SwiftUI

/// An actor or director: who they are, and the work of theirs you can watch.
///
/// Pushed onto the `NavigationStack` that `DetailScreen` owns, so it arrives with a normal back
/// button. Opening a title from here presents a cover from THIS screen rather than routing through
/// `AppRouter` — Detail is already a cover owned by the shell, and that shell silently ignores a
/// request to stack a second one (the constraint `SimilarRail` documents). That also caps the
/// presentation at one cover deep however far you wander person → film → person.
struct PersonScreen: View {
    let ref: TMDBPersonRef

    @Environment(AppSession.self) private var session
    /// Built here rather than read from the environment. Detail is a full-screen cover and this
    /// page is pushed inside it, and the shell's `TileWatchMarks` does not survive that boundary —
    /// reading it as a non-optional `@Environment` traps the moment the page appears.
    @State private var marks: TileWatchMarks?
    @State private var store: PersonStore?
    /// A title opened from this page. Owned or not, it is the same page — `MediaItem.placeholder`
    /// stands in for something not in the library yet.
    @State private var openTitle: MediaItem?

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 100, maximum: 160), spacing: Theme.Space.md)]
    }

    var body: some View {
        Group {
            if let store {
                content(store)
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Palette.canvas.ignoresSafeArea())
        .navigationTitle(store?.name ?? ref.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if marks == nil { marks = session.makeTileWatchMarks() }
            if store == nil { store = session.makePersonStore(for: ref) }
            await store?.load()
        }
        // `AnyView` is load-bearing: without it this body's type would contain itself through
        // DetailScreen, which pushes this very view.
        .fullScreenCover(item: $openTitle) { item in
            if let details = session.detailsProvider {
                AnyView(DetailScreen(item: item, details: details, watch: session.watchStore,
                                     profileID: session.activeProfileID,
                                     myList: session.myListStore,
                                     ratings: session.ratingsProvider,
                                     versionPrefs: session.versionPreferences,
                                     letterboxd: session.letterboxdRatingProvider))
            }
        }
    }

    @ViewBuilder private func content(_ store: PersonStore) -> some View {
        switch store.state {
        case .idle, .loading:
            ProgressView()
        case .failed(let reason):
            message(reason, systemImage: "exclamationmark.triangle")
        case .empty:
            message("Nothing of \(store.name)'s to show.", systemImage: "film")
        case .loaded:
            loaded(store)
        }
    }

    private func loaded(_ store: PersonStore) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                header(store)
                if !store.acting.isEmpty { section("AS ACTOR", hits: store.acting) }
                if !store.directing.isEmpty { section("AS DIRECTOR", hits: store.directing) }
            }
            .padding(Theme.Space.lg)
        }
        // One batched read for everything on the page, so a title you have already seen says so.
        .task(id: store.acting.first?.id ?? store.directing.first?.id ?? "") {
            await marks?.load(store.acting + store.directing)
        }
    }

    private func header(_ store: PersonStore) -> some View {
        HStack(spacing: Theme.Space.lg) {
            RemoteImage(url: TMDBClient.imageURL(path: store.profilePath, size: "w185")) {
                Theme.Palette.surface2.overlay {
                    Image(systemName: "person.fill").foregroundStyle(Theme.Palette.textTertiary)
                }
            }
            .frame(width: 96, height: 96)
            .clipShape(Circle())
            .overlay { Circle().strokeBorder(Theme.Palette.hairline, lineWidth: 1) }

            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text(store.name).font(Theme.Typo.title())
                    .foregroundStyle(Theme.Palette.textPrimary)
                if let knownFor = store.knownFor {
                    Text(knownFor).font(Theme.Typo.caption())
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func section(_ title: String, hits: [SearchHit]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text(title).font(Theme.Typo.label()).tracking(1.5)
                .foregroundStyle(Theme.Palette.gold)
            LazyVGrid(columns: columns, alignment: .leading, spacing: Theme.Space.xl) {
                ForEach(hits) { tile($0) }
            }
        }
    }

    /// The same decision the Find grid makes: owned or not, a title opens the same page. Read live,
    /// so a title added while this page is open flips on the next render.
    private func tile(_ hit: SearchHit) -> some View {
        let owned = session.libraryStore?.ownedItem(tmdbID: hit.result.id)
        let watched = marks?.isWatched(hit) ?? false
        return Button {
            openTitle = owned ?? .placeholder(for: hit)
        } label: {
            PosterCard(title: hit.result.displayTitle,
                       posterURL: TMDBClient.imageURL(path: hit.result.posterPath, size: "w342"),
                       width: nil)
                .opacity(watched ? 0.55 : 1)
        }
        .pressable()
    }

    private func message(_ text: String, systemImage: String) -> some View {
        VStack(spacing: Theme.Space.md) {
            Image(systemName: systemImage).font(.largeTitle)
                .foregroundStyle(Theme.Palette.textSecondary)
            Text(text).font(Theme.Typo.body()).multilineTextAlignment(.center)
                .foregroundStyle(Theme.Palette.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Theme.Space.xl)
    }
}
