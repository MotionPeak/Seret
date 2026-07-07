import DebridCore
import DebridUI
import SwiftUI

/// A browse tab (Movies or TV): the kind's `DiscoverStore` rows (For You / Trending / …). Search is
/// a SEPARATE full-screen screen opened by the Search button, so navigating the rows never pops the
/// keyboard. Owned titles get an "In Library" badge and push their library Detail; new titles push
/// the Add flow. (Destinations are registered by the shell.)
struct BrowseScreen<Leading: View>: View {
    let kind: MediaKind
    /// Extra pills rendered at the START of the segment row (e.g. Find's Movies/Shows filter), so the
    /// filter shares the one reachable row with search + the discover segments instead of a row above
    /// that the focus engine skips when you press Down from the nav bar.
    @ViewBuilder var leading: () -> Leading

    @Environment(AppSession.self) private var session
    /// Which segment pill has focus — moving across them switches the section live (no press).
    @FocusState private var focusedSegment: DiscoverStore.Segment?

    private var browse: DiscoverStore? { kind == .movie ? session.moviesBrowse : session.showsBrowse }

    var body: some View {
        rows
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(CanvasBackground())
    }

    @ViewBuilder private var rows: some View {
        if let browse {
            VStack(alignment: .leading, spacing: 0) {
                segmentPicker(browse).padding(.leading, 60).padding(.bottom, 8)
                segmentContent(browse)
            }
            // Load the selected segment whenever it changes (and on first show). Keyed on kind TOO,
            // so Find's Movies→Shows flip re-fires the load even when both stores sit on the same
            // segment (else the id wouldn't change and the new kind's rails would stay stuck loading).
            .task(id: "\(kind.rawValue)/\(browse.selectedSegment.rawValue)") {
                await browse.loadSegment(browse.selectedSegment)
            }
        } else {
            SeretLoader()
        }
    }

    @ViewBuilder private func segmentContent(_ browse: DiscoverStore) -> some View {
        Group {
            switch browse.segmentState(browse.selectedSegment) {
            case .idle, .loading:
                BrowseSkeleton()                          // something to look at — not a black void
            case .failed:
                VStack(spacing: 24) {
                    Image(systemName: "exclamationmark.triangle").font(.system(size: 54))
                        .foregroundStyle(Theme.Palette.textSecondary)
                    Text("Couldn't load.").sectionTitle()
                    Button("Retry") { Task { await browse.loadSegment(browse.selectedSegment) } }
                        .buttonStyle(SeretPillStyle(selected: false))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loaded:
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 44) {
                        ForEach(browse.rows) { row in
                            rail(title: row.title, hits: row.hits, cam: false)
                        }
                    }
                    .padding(.vertical, 20)
                }
            }
        }
    }

    /// Search button + For You / Trending / New / Popular / Top Rated selector. Commit-on-press: moving
    /// focus across the pills only highlights them; a click on a pill switches the section — consistent
    /// with the top nav bar, so gliding the remote never reloads a rail set by accident. Search is an
    /// explicit button so the keyboard never opens just from navigating. Value-based like every other
    /// push — a view-destination link inside the shell's path-bound NavigationStack bypasses `path`, so
    /// `path.isEmpty` (which drives the tab bar) stops reflecting reality.
    private func segmentPicker(_ browse: DiscoverStore) -> some View {
        HStack(spacing: 16) {
            leading()
            NavigationLink(value: BrowseDestination.search(kind)) { Image(systemName: "magnifyingglass") }
                .buttonStyle(SeretPillStyle(selected: false))
            ForEach(DiscoverStore.Segment.allCases) { seg in
                Button(seg.title) { browse.select(seg) }
                    .buttonStyle(SeretPillStyle(selected: seg == browse.selectedSegment))
                    .focused($focusedSegment, equals: seg)
            }
        }
    }

    private func rail(title: String, hits: [SearchHit], cam: Bool) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if !title.isEmpty { Text(title).sectionTitle().padding(.leading, Theme.Layout.contentMargin) }
            ScrollView(.horizontal) {
                LazyHStack(spacing: 36) {
                    ForEach(hits) { BrowseTile(hit: $0, cam: cam || (browse?.isCAM($0.result) ?? false)) }
                }
                .padding(.horizontal, Theme.Layout.contentMargin).padding(.vertical, 40)
            }
            .scrollClipDisabled()
        }
    }

}

/// Loading state for a browse segment — a few redacted poster rails so the screen reads as
/// "filling in" rather than flashing black while the genre rails fan out.
private struct BrowseSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 44) {
            ForEach(0..<3, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 16) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Theme.Palette.surface2)
                        .frame(width: 280, height: 30)
                        .padding(.leading, Theme.Layout.contentMargin)
                    HStack(spacing: 36) {
                        ForEach(0..<6, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: Theme.Layout.posterCorner, style: .continuous)
                                .fill(Theme.Palette.surface2)
                                .frame(width: 220, height: 330)
                        }
                    }
                    .padding(.horizontal, Theme.Layout.contentMargin)
                }
            }
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Where a browse/search poster goes: the owned item's library Detail, the Add flow, or the
/// full-screen Search. ONE value type so a tile is ONE stable `NavigationLink` — see BrowseTile.
enum BrowseDestination: Hashable {
    case detail(MediaItem)
    case add(SearchHit)
    case search(MediaKind)
}

/// A focusable browse poster. Owned → pushes the library Detail; else the Add flow. Owned posters
/// carry an "In Library" badge. Shared by Browse + Search.
///
/// ⚠️ The link must be ONE stable view whose VALUE varies — not an owned/not-owned branch of two
/// links. The background library load flips `ownedItem` while the user browses; a branch swap
/// destroys the focused tile, tvOS silently drops focus back to the first stable element (the
/// Search pill), and the next click opened the search keyboard instead of the title.
struct BrowseTile: View {
    let hit: SearchHit
    var cam: Bool = false
    @Environment(AppSession.self) private var session
    private let width: CGFloat = 220
    private let height: CGFloat = 330

    var body: some View {
        let owned = session.libraryStore?.ownedItem(tmdbID: hit.result.id)
        // No title label — posters already carry their title in the artwork.
        return NavigationLink(value: owned.map(BrowseDestination.detail) ?? .add(hit)) {
            poster(owned: owned != nil)
        }
        .buttonStyle(.card)
    }

    @ViewBuilder private func poster(owned: Bool) -> some View {
        ZStack(alignment: .topTrailing) {
            if let url = TMDBClient.imageURL(path: hit.result.posterPath, size: "w500") {
                RemoteImage(url: url)
                    .frame(width: width, height: height)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.posterCorner, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: Theme.Layout.posterCorner, style: .continuous)
                    .fill(Theme.Palette.surface1)
                    .overlay {
                        Text(hit.result.displayTitle).cardTitle().foregroundStyle(Theme.Palette.textSecondary)
                            .multilineTextAlignment(.center).padding(12)
                    }
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
