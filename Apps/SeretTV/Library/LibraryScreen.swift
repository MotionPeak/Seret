import DebridCore
import DebridUI
import SwiftUI

/// Renders one tab (Movies or Shows): the poster grid when loaded, otherwise the
/// loading / empty / failed state. `items` is the kind-filtered slice from the store;
/// `state` is the store's overall load state. The section is labeled by the tab bar, so
/// `title` drives only the empty-state copy ("No movies yet") — no in-content nav title.
/// Transparent: the page behind it (My Library) draws the focus-following backdrop.
///
/// The Downloading strip (`downloads`) is the FIRST item of the same scroll, in every state, so it
/// scrolls away above the grid. Pinned above the grid, its 236×354 cards left the grid a viewport
/// shorter than one poster: the focused first row sat cut off at the bottom of the screen and could
/// never scroll into view. One scroll in every state also means the strip never moves between two
/// containers when the library finishes loading — a card focused then is never rebuilt.
struct LibraryScreen: View {
    let title: String
    let items: [MediaItem]
    let state: LibraryStore.State
    let onRetry: () -> Void
    var watchedIDs: Set<String> = []
    let session: AppSession
    var onRemove: (MediaItem) -> Void = { _ in }
    /// A grid card took focus.
    var onFocus: (MediaItem) -> Void = { _ in }
    /// Downloads in flight, shown above the grid.
    var downloads: [DownloadTile] = []

    /// The top fade's band, and the scroll's top inset to match.
    private static let fadeBand: CGFloat = 50

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if !downloads.isEmpty {
                    DownloadingStrip(tiles: downloads, library: session.libraryStore)
                        .focusSection()
                }
                content
            }
            // The top of the scroll at rest sits below the fade band, so the strip's title is
            // never dimmed until it actually scrolls under the pills.
            .padding(.top, Self.fadeBand)
        }
        .gridTopFade(Self.fadeBand)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private var content: some View {
        switch state {
        case .loading:
            SeretLoader(label: "Loading your library…")
                .frame(maxWidth: .infinity)
                .containerRelativeFrame(.vertical)
        case .failed(let msg):
            message(msg, systemImage: "exclamationmark.triangle", action: ("Try Again", onRetry))
        case .empty:
            message("Nothing in your Real‑Debrid library yet.", systemImage: "tray", action: nil)
        case .loaded:
            if items.isEmpty {
                message("No \(title.lowercased()) yet.", systemImage: "tray", action: nil)
            } else {
                PosterGrid(items: items, watchedIDs: watchedIDs,
                           session: session, onRemove: onRemove, onFocus: onFocus)
            }
        }
    }

    private func message(_ text: String, systemImage: String,
                         action: (label: String, run: () -> Void)?) -> some View {
        VStack(spacing: 28) {
            Image(systemName: systemImage).font(.system(size: 64)).foregroundStyle(Theme.Palette.textSecondary)
            Text(text).sectionTitle().multilineTextAlignment(.center).frame(maxWidth: 700)
                .foregroundStyle(Theme.Palette.textSecondary)
            if let action {
                Button(action.label, action: action.run).buttonStyle(SeretActionButtonStyle())
            }
        }
        .frame(maxWidth: .infinity)
        .containerRelativeFrame(.vertical)   // centred in the visible page, inside the scroll
    }
}
