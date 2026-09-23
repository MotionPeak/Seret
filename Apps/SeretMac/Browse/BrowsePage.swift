import DebridCore
import DebridUI
import SwiftUI

/// The `.movies` / `.shows` section root: resolves `BrowseSources` from the environment (the
/// harness injects one via `\.previewBrowse`) or the live session's per-kind `DiscoverStore`s.
struct BrowseRoot: View {
    let kind: MediaKind

    @Environment(\.previewBrowse) private var previewBrowse: BrowseSources?
    @Environment(AppSession.self) private var session: AppSession?

    private var sources: BrowseSources {
        previewBrowse ?? BrowseSources(movies: session?.moviesBrowse, shows: session?.showsBrowse,
                                       makeGenreGrid: { kind, genre in session?.makeGenreGrid(kind: kind, genre: genre) })
    }

    var body: some View {
        BrowsePage(kind: kind, sources: sources)
    }
}

/// Movies / Shows: a header, the genre strip, and either the All segment's rails or a genre's grid
/// underneath. The chosen genre is remembered per kind on `ShellModel` (Decision 5).
struct BrowsePage: View {
    let kind: MediaKind
    let sources: BrowseSources

    @Environment(ShellModel.self) private var shell: ShellModel?
    @Environment(\.pageLeadingInset) private var pageLeadingInset

    private var selectedGenre: DiscoverStore.Genre? { shell?.browseGenre[kind] }
    private var discover: DiscoverStore? { sources.discover(for: kind) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                GenreStrip(kind: kind, selected: selectedGenre) { genre in
                    shell?.setBrowseGenre(genre, for: kind)
                }
                pageBody
            }
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        Text(kind == .movie ? "Movies" : "Shows")
            .font(Theme.Typo.titleXL())
            .foregroundStyle(Theme.Palette.textPrimary)
            .padding(.leading, pageLeadingInset)
            .padding(.top, 54)
    }

    @ViewBuilder private var pageBody: some View {
        if let selectedGenre {
            GenreGridPage(kind: kind, genre: selectedGenre, sources: sources)
        } else if let discover {
            SegmentRails(store: discover, kind: kind)
        } else {
            VStack(alignment: .leading, spacing: 26) {
                RailSkeleton()
                RailSkeleton()
                RailSkeleton()
            }
        }
    }
}
