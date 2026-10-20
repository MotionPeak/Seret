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
///
/// ⚠️ The strip comes and goes ABOVE the grid in the same scroll: a first download starting, or the
/// last one finishing, grows or shrinks the content above the focused cell by ~480pt, and tvOS does
/// not re-scroll when focus did not move — the focused cell jumped under the pills or off screen.
/// Scrolling it back does not work: measured, a programmatic scroll while the focused cell is off
/// screen makes tvOS hand focus to a visible cell (Heat → Dune: Part Two in
/// `-uiPreview librarydownloadstarts`). So the strip never changes SHAPE while focus is inside this
/// scroll (a grid cell or a strip card): it keeps showing what it showed — its last cards, or
/// nothing — and takes its new shape once focus leaves (the pills, the side menu, a pushed page).
/// While its shape holds, live tiles still flow in: only appearing and disappearing wait.
///
/// The hold is decided IN the body (`ScrollFocusTracker.tiles(for:)`), not in an `onChange`: an
/// `onChange` runs after the body has already laid the new shape out once, and that one transient
/// layout was enough — measured — to push the focused cell off screen and lose its focus.
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
    /// A Downloading card took focus.
    var onFocusDownload: (DownloadTile) -> Void = { _ in }

    /// Which view in this scroll has focus, and the strip it last showed. A reference in `@State`:
    /// written on every focus move, never observed, so a move never re-renders the page.
    @State private var scrollFocus = ScrollFocusTracker()
    /// Bumped when focus has left the scroll while the strip's shape was held: one re-render, in
    /// which the strip takes its new shape.
    @State private var releaseHold = 0

    /// The top fade's band, and the scroll's top inset to match.
    private static let fadeBand: CGFloat = 50

    var body: some View {
        let _ = releaseHold      // read, so a release re-renders
        let stripTiles = scrollFocus.tiles(for: downloads)
        return ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if !stripTiles.isEmpty {
                    DownloadingStrip(tiles: stripTiles, library: session.libraryStore,
                                     onFocus: onFocusDownload, onFocusChange: scrollFocusChanged)
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

    /// Focus arrived at (true) or left (false) the view `id` in this scroll. Once focus has left
    /// the scroll altogether — settled, since a move between two cells passes through "nothing
    /// focused" for an instant — a held strip takes its new shape.
    private func scrollFocusChanged(_ id: String, _ focused: Bool) {
        let tracker = scrollFocus
        if focused {
            tracker.focusedID = id
            tracker.leaving?.cancel()
            return
        }
        guard tracker.focusedID == id else { return }
        tracker.focusedID = nil
        let release = $releaseHold
        tracker.leaving = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled, tracker.focusedID == nil, tracker.holding else { return }
            release.wrappedValue += 1
        }
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
                           session: session, onRemove: onRemove, onFocus: onFocus,
                           onFocusChange: scrollFocusChanged)
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

/// Which view in a scroll has focus — see `LibraryScreen.scrollFocusChanged`.
@MainActor
final class ScrollFocusTracker {
    /// The focused view's id; nil while focus is anywhere else.
    var focusedID: String?
    /// The settle before "focus has left" counts.
    var leaving: Task<Void, Never>?
    /// The strip's cards as last shown.
    private(set) var shown: [DownloadTile] = []
    /// The strip is showing a shape other than the live one.
    private(set) var holding = false

    /// The cards the strip shows for the live `downloads`: those, unless focus is inside the scroll
    /// and they would make the strip appear or disappear — then the strip keeps its last cards.
    func tiles(for downloads: [DownloadTile]) -> [DownloadTile] {
        if focusedID == nil || shown.isEmpty == downloads.isEmpty {
            shown = downloads
            holding = false
        } else {
            holding = true
        }
        return shown
    }
}
