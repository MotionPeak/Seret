import DebridCore
import DebridUI
import SwiftUI

/// A browse tab (Movies or TV): `.searchable` scoped to the kind over the kind's `DiscoverStore`
/// rows when idle, search results when typing. Owned titles get an "In Library" badge and push
/// their library Detail; new titles push the Add flow. (Destinations are registered by the shell.)
struct BrowseScreen: View {
    let kind: MediaKind

    @Environment(AppSession.self) private var session
    @State private var query = ""
    /// The title under remote focus — drives the full-bleed hero. Tiles publish it via FocusedHitKey.
    @State private var featuredHit: SearchHit?

    private var browse: DiscoverStore? { kind == .movie ? session.moviesBrowse : session.showsBrowse }

    var body: some View {
        Group {
            if let search = session.searchStore {
                content(search)
                    .searchable(text: $query, placement: .automatic,
                                prompt: kind == .movie ? "Search movies" : "Search shows")
                    .task(id: query) {
                        try? await Task.sleep(for: .milliseconds(350))
                        guard !Task.isCancelled else { return }
                        await search.search(query: query, kind: kind)
                    }
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CanvasBackground())
    }

    @ViewBuilder private func content(_ search: SearchStore) -> some View {
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            rows
        } else {
            switch search.state {
            case .idle, .searching:
                ProgressView("Searching…").font(.title3)
            case .empty:
                message("No results.", systemImage: "magnifyingglass")
            case .failed(let msg):
                message(msg, systemImage: "exclamationmark.triangle")
            case .results:
                resultsGrid(search.results)
            }
        }
    }

    @ViewBuilder private var rows: some View {
        if let browse {
            switch browse.state {
            case .idle, .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                    .task(id: kind) { await browse.load() }   // kick off the feed (self-guards re-runs)
            case .failed:
                VStack(spacing: 28) {
                    Image(systemName: "exclamationmark.triangle").font(.system(size: 64)).foregroundStyle(.secondary)
                    Text("Couldn't load.").font(.title3)
                    Button("Retry") { Task { await browse.load() } }.buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loaded:
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 40) {
                        HeroBanner(hit: featuredHit)   // scrolls with content; crossfades on focus
                        segmentPicker(browse).padding(.leading, 60)
                        ForEach(browse.rows) { row in
                            rail(title: row.title, hits: row.hits, cam: false)
                        }
                    }
                    .padding(.bottom, 20)
                }
                .onPreferenceChange(FocusedHitKey.self) { featuredHit = $0 ?? featuredHit }
                .onAppear { if featuredHit == nil { featuredHit = browse.rows.first?.hits.first } }
            }
        }
    }

    /// Trending / New Releases / Popular selector — a focusable pill row (segmented Pickers don't
    /// take focus well on tvOS). Switching is instant (all segments loaded up front).
    private func segmentPicker(_ browse: DiscoverStore) -> some View {
        HStack(spacing: 16) {
            ForEach(DiscoverStore.Segment.allCases) { seg in
                Button(seg.title) { browse.select(seg) }
                    .buttonStyle(SeretPillStyle(selected: seg == browse.selectedSegment))
            }
        }
    }

    private func rail(title: String, hits: [SearchHit], cam: Bool) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if !title.isEmpty { Text(title).font(.title2.bold()).padding(.leading, 60) }
            ScrollView(.horizontal) {
                LazyHStack(spacing: 40) {
                    ForEach(hits) { BrowseTile(hit: $0, cam: cam || (browse?.isCAM($0.result) ?? false)) }
                }
                .padding(.horizontal, 60).padding(.vertical, 40)
            }
            .scrollClipDisabled()
        }
    }

    private func resultsGrid(_ hits: [SearchHit]) -> some View {
        let columns = [GridItem(.adaptive(minimum: 220, maximum: 260), spacing: 50)]
        return ScrollView {
            LazyVGrid(columns: columns, spacing: 50) {
                ForEach(hits) { BrowseTile(hit: $0, cam: browse?.isCAM($0.result) ?? false) }
            }
            .padding(60)
        }
    }

    private func message(_ text: String, systemImage: String) -> some View {
        VStack(spacing: 28) {
            Image(systemName: systemImage).font(.system(size: 64)).foregroundStyle(.secondary)
            Text(text).font(.title3).multilineTextAlignment(.center).frame(maxWidth: 700)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A focusable browse poster. Owned → pushes the library `MediaItem` (Detail); else the
/// `SearchHit` (Add flow). Owned posters carry an "In Library" badge.
private struct BrowseTile: View {
    let hit: SearchHit
    var cam: Bool = false
    @Environment(AppSession.self) private var session
    @FocusState private var focused: Bool
    private let width: CGFloat = 220
    private let height: CGFloat = 330

    var body: some View {
        let owned = session.libraryStore?.ownedItem(tmdbID: hit.result.id)
        return VStack(alignment: .leading, spacing: 12) {
            if let owned {
                NavigationLink(value: owned) { poster(owned: true) }.buttonStyle(.card).focused($focused)
            } else {
                NavigationLink(value: hit) { poster(owned: false) }.buttonStyle(.card).focused($focused)
            }
            Text(hit.result.displayTitle)
                .font(.callout.weight(.semibold)).lineLimit(1)
                .frame(width: width, alignment: .leading)
        }
        // Publish this title to the hero while focused (the screen keeps the last non-nil).
        .preference(key: FocusedHitKey.self, value: focused ? hit : nil)
    }

    @ViewBuilder private func poster(owned: Bool) -> some View {
        ZStack(alignment: .topTrailing) {
            if let url = TMDBClient.imageURL(path: hit.result.posterPath, size: "w500") {
                AsyncImage(url: url) { $0.resizable().aspectRatio(contentMode: .fill) }
                    placeholder: { ZStack { Rectangle().fill(.gray.opacity(0.18)); ProgressView() } }
                    .frame(width: width, height: height).clipped()
            } else {
                Rectangle().fill(.gray.opacity(0.3))
                    .overlay { Text(hit.result.displayTitle).font(.headline).multilineTextAlignment(.center).padding(12) }
                    .frame(width: width, height: height)
            }
            if owned {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.black, .yellow)
                    .padding(10)
            } else if cam {
                Text("CAM")
                    .font(.system(size: 15, weight: .heavy)).foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Color.red.opacity(0.85), in: Capsule())
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)   // CAM tag top-leading
            }
        }
    }
}
