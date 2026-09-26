import DebridCore
import DebridUI
import SwiftUI

/// Which of a person's two filmography sections to show, and in what order. Pure — no view state —
/// so the "known for Directing → Director section first" rule is tested without mounting a page.
enum PersonSections {
    enum Section: Equatable, Hashable { case acting, directing }

    /// Both non-empty sections; someone TMDB lists as known for "Directing" gets As Director
    /// first. Empty sections are dropped rather than shown blank.
    static func make(actingCount: Int, directingCount: Int, knownFor: String?) -> [Section] {
        let directingFirst = knownFor == "Directing"
        var sections: [Section] = []
        if directingFirst, directingCount > 0 { sections.append(.directing) }
        if actingCount > 0 { sections.append(.acting) }
        if !directingFirst, directingCount > 0 { sections.append(.directing) }
        return sections
    }
}

/// What a pushed `.person` route renders: the harness's injected `PersonStore` when there is one,
/// otherwise one built from the session — the same seam `TitleRoute` reads for `DetailStore`.
struct PersonRoute: View {
    let ref: TMDBPersonRef

    @Environment(PersonStore.self) private var injected: PersonStore?
    @Environment(AppSession.self) private var session: AppSession?
    @State private var store: PersonStore?

    var body: some View {
        Group {
            if let store {
                PersonPage(store: store)
            } else {
                Color.clear
            }
        }
        .task {
            guard store == nil else { return }
            store = injected ?? session?.makePersonStore(for: ref)
        }
    }
}

/// An actor or director: headshot, name, "Known for …", and every title of theirs you can reach —
/// through the same `PosterTile` every rail and grid uses, so ownership, watched marks and the
/// watchlist all read exactly as they do everywhere else.
struct PersonPage: View {
    let store: PersonStore

    @Environment(AppSession.self) private var session: AppSession?
    @Environment(ShellModel.self) private var shell: ShellModel?
    @Environment(LibraryStore.self) private var injectedLibrary: LibraryStore?
    @Environment(\.pageLeadingInset) private var pageLeadingInset
    /// Built here, not read from the environment — a shell object does not reliably survive this
    /// push boundary (M2's own lesson, restated in Task 6's plan for this exact page).
    @State private var marks: TileWatchMarks?
    @State private var watchlist: WatchlistMarks?

    private var library: LibraryStore? { injectedLibrary ?? session?.libraryStore }
    private var performer: PosterActionPerformer {
        PosterActionPerformer(session: session, shell: shell, library: library, marks: marks, watchlist: watchlist)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                header
                content
            }
            .padding(.leading, pageLeadingInset)
            .padding(.trailing, 28)
            .padding(.top, 54)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .environment(marks ?? .placeholder)
        .environment(watchlist ?? .placeholder)
        .task {
            if marks == nil { marks = session?.makeTileWatchMarks() }
            if watchlist == nil { watchlist = session?.makeWatchlistMarks() }
            await watchlist?.load()
            await store.load()
            await marks?.load(store.acting + store.directing)
        }
    }

    // MARK: - Header

    @ViewBuilder private var header: some View {
        if store.state == .idle || store.state == .loading {
            HStack(alignment: .center, spacing: 24) {
                ShimmerView(cornerRadius: 66).frame(width: 132, height: 132)
                VStack(alignment: .leading, spacing: 10) {
                    ShimmerView(cornerRadius: 4).frame(width: 220, height: 26)
                    ShimmerView(cornerRadius: 4).frame(width: 140, height: 13)
                }
            }
        } else {
            HStack(alignment: .center, spacing: 24) {
                RemoteImage(url: TMDBClient.imageURL(path: store.profilePath, size: "w342")) { headshotPlaceholder }
                    .frame(width: 132, height: 132)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(Theme.Palette.gold.opacity(0.7), lineWidth: 1))
                VStack(alignment: .leading, spacing: 6) {
                    Text(store.name)
                        .font(.system(size: 30, weight: .heavy))
                        .foregroundStyle(Theme.Palette.textPrimary)
                    if let knownFor = store.knownFor {
                        Text("Known for \(knownFor)")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.Palette.textSecondary)
                    }
                }
            }
        }
    }

    private var headshotPlaceholder: some View {
        Circle().fill(Theme.Palette.surface2).overlay {
            Image(systemName: "person.fill")
                .font(.system(size: 44))
                .foregroundStyle(.white.opacity(0.2))
        }
    }

    // MARK: - Content

    @ViewBuilder private var content: some View {
        switch store.state {
        case .idle, .loading:
            PosterGrid(items: [SearchHit](), isLoading: true) { (hit: SearchHit) in tile(hit) }
        case .empty:
            Text("Nothing of theirs is on TMDB yet.")
                .font(.system(size: 15))
                .foregroundStyle(Theme.Palette.textSecondary)
        case .failed(let message):
            VStack(alignment: .leading, spacing: 12) {
                Text(message)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.Palette.textSecondary)
                Button("Try Again") { Task { await store.load() } }
                    .buttonStyle(GlassButtonStyle())
            }
        case .loaded:
            VStack(alignment: .leading, spacing: 30) {
                ForEach(PersonSections.make(actingCount: store.acting.count,
                                            directingCount: store.directing.count,
                                            knownFor: store.knownFor), id: \.self) { section in
                    switch section {
                    case .acting: posterSection("AS ACTOR", hits: store.acting)
                    case .directing: posterSection("AS DIRECTOR", hits: store.directing)
                    }
                }
            }
        }
    }

    private func posterSection(_ title: String, hits: [SearchHit]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(Theme.Typo.label())
                .tracking(1.5)
                .foregroundStyle(Theme.Palette.gold)
            PosterGrid(items: hits,
                       prefetchURL: { TMDBClient.imageURL(path: $0.result.posterPath, size: "w342") }) { hit in tile(hit) }
        }
    }

    private func tile(_ hit: SearchHit) -> some View {
        let model = PosterTileModel.hit(hit, library: library, isCAM: false)
        let watched = marks?.isWatched(hit) ?? false
        let onWatchlist = model.watchlistFilm.map { watchlist?.contains(tmdbID: $0.tmdbID) ?? false } ?? false
        let badge: WatchBadge = watched ? .watched : .none
        let decor = PosterDecor(owned: model.owned != nil, onWatchlist: onWatchlist, dimsWatched: true)
        return PosterTile(model: model, state: PosterTileState(badge: badge, decor: decor),
                          actions: .make(kind: hit.kind, owned: model.owned != nil, watched: watched, onWatchlist: onWatchlist),
                          perform: performer.perform)
    }
}
