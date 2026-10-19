import DebridCore
import DebridUI
import SwiftUI

/// Layout constants shared by `FocusBrowsePage`, `PlexRail` and the pages built on them — one
/// place to tune the Plex frame. Not on `FocusBrowsePage` itself: a generic type cannot hold
/// stored statics, and a rail must read these without naming the page's `Rails` type.
enum FocusBrowseLayout {
    /// Where titles, the header text and the first tile start, measured inside the shell's content
    /// area (which already clears the side menu).
    static let leadingInset: CGFloat = 90
    /// The fixed preview header, from the top of the safe area to the top of the rail area.
    static let headerHeight: CGFloat = 470
    /// Header text starts this far below the safe area — 60 + 50 = the mockup's 110.
    static let headerTopPadding: CGFloat = 50
    /// Room above and below each rail's tiles for the focus lift, ring and shadow.
    static let railVerticalPadding: CGFloat = 36
    /// Overlaps consecutive rails' paddings, so the rail pitch is the mockup's ~450pt and the next
    /// rail's title peeks in at the bottom of the screen. Exactly one padding: the rail above the
    /// focused one then ends flush with the top of the rail area, so no sliver of its tiles shows
    /// through the top fade. One padding still keeps a lifted tile clear of the next title.
    static let railSpacing: CGFloat = -36
    /// Empty space after the last rail, so it too can scroll up to the top of the rail area.
    static let bottomRunway: CGFloat = 160
    /// How long a newly settled subject may wait for its art (logo, rating, backdrop) before the
    /// header switches anyway. Waiting means the header and backdrop change ONCE, together,
    /// instead of title-then-logo and backdrop-then-better-backdrop.
    static let settleBudget: Duration = .milliseconds(450)
}

/// A Plex-style browse page: a fixed preview header describing the focused tile, over an
/// ultrablur backdrop of its art, above a vertical stack of `PlexRail`s.
///
/// - The header follows `preview.shown`, which the tiles drive through `FocusPreviewModel.focus`
///   (debounced, so gliding along a rail never re-renders the header or backdrop per tile).
/// - When focus enters a rail, the rail scrolls to the top of the rail area, so the focused row
///   always sits in the same place under the header — calm and predictable, like Plex.
/// - The page reads `TitleArtStore` results only: its `.task(id:)` asks the store to load the
///   shown subject's art (the store owns the fetch), and the body looks up the art for the
///   subject it is displaying — so an older title's art can never paint over a newer one.
struct FocusBrowsePage<Rails: View>: View {
    @Bindable var preview: FocusPreviewModel
    let art: TitleArtStore?
    @ViewBuilder var rails: Rails

    static var leadingInset: CGFloat { FocusBrowseLayout.leadingInset }

    /// The subject the header and backdrop show — `preview.shown` once its art has settled.
    @State private var displayed: PreviewSubject?
    /// The row focus is in, as reported by `plexBrowseRow(id:)`.
    @State private var focusedRow: String?

    init(preview: FocusPreviewModel, art: TitleArtStore?, @ViewBuilder rails: () -> Rails) {
        self.preview = preview
        self.art = art
        self.rails = rails()
    }

    var body: some View {
        let shownArt = displayed.flatMap(artFor)
        VStack(alignment: .leading, spacing: 0) {
            FocusPreviewHeader(subject: displayed, art: shownArt)
                .padding(.top, FocusBrowseLayout.headerTopPadding)
                .padding(.leading, FocusBrowseLayout.leadingInset)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: FocusBrowseLayout.headerHeight, alignment: .top)

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: FocusBrowseLayout.railSpacing) {
                        rails
                    }
                    .padding(.bottom, FocusBrowseLayout.bottomRunway)
                }
                // Rails scroll edge to edge (a tile scrolled left runs on under the side menu, as in
                // Plex) — but a rail leaving the top must dissolve, not be sliced against the
                // header. The fade band is the focused rail's own top padding, so it never touches
                // the focused rail's title.
                .scrollClipDisabled()
                .gridTopFade(FocusBrowseLayout.railVerticalPadding)
                .onChange(of: focusedRow) { _, row in
                    guard let row else { return }
                    withAnimation(Theme.Anim.railScroll) { proxy.scrollTo(row, anchor: .top) }
                }
            }
            // Rails run to the bottom of the screen, so the next rail's title peeks in.
            .ignoresSafeArea(edges: .bottom)
        }
        .background { backdrop(path: displayed.flatMap { shownArt?.backdropPath ?? $0.backdropPath }) }
        .environment(\.focusBrowseRowFocused, { focusedRow = $0 })
        .task(id: preview.shown?.id) { await settle(preview.shown) }
    }

    /// The backdrop, full-bleed: out past the safe area AND past the shell's leading inset, so the
    /// art runs under the side menu as it does in Plex.
    private func backdrop(path: String?) -> some View {
        GeometryReader { geo in
            let lead = max(0, geo.frame(in: .global).minX)
            UltrablurBackdrop(backdropPath: path)
                .frame(width: geo.size.width + lead, height: geo.size.height)
                .offset(x: -lead)
        }
        .ignoresSafeArea()
    }

    private func artFor(_ subject: PreviewSubject) -> TitleArt? {
        guard let art, let id = subject.tmdbID else { return nil }
        return art.art(for: subject.kind, tmdbID: id)
    }

    /// Moves the header and backdrop to `subject` once its art is ready, or once the budget runs
    /// out. A newer subject cancels this task, so only the latest ever lands.
    private func settle(_ subject: PreviewSubject?) async {
        guard let subject else {
            withAnimation(Theme.Anim.previewOut) { displayed = nil }
            return
        }
        guard subject != displayed else { return }
        let warmed = SettleFlag()
        let store = art
        // Unstructured on purpose: if this settle is superseded the warm-up still finishes and
        // fills the caches (the store owns the details fetch either way).
        Task {
            await FocusPreviewWarmer.warm(subject, art: store)
            warmed.done = true
        }
        let deadline = ContinuousClock.now.advanced(by: FocusBrowseLayout.settleBudget)
        while !warmed.done, ContinuousClock.now < deadline {
            do { try await Task.sleep(for: .milliseconds(20)) } catch { return }
        }
        guard !Task.isCancelled else { return }
        withAnimation(Theme.Anim.previewIn) { displayed = subject }
    }
}

@MainActor
private final class SettleFlag {
    var done = false
}

/// Brings everything the header and backdrop draw for a subject into memory: its `TitleArt`, the
/// logo bitmap, and both backdrop layers.
@MainActor
enum FocusPreviewWarmer {
    static func warm(_ subject: PreviewSubject, art store: TitleArtStore?) async {
        var art: TitleArt?
        if let store, let id = subject.tmdbID {
            art = await store.load(subject.kind, tmdbID: id)
        }
        let logoPath = art?.logoPath
        let backdropPath = art?.backdropPath ?? subject.backdropPath
        async let logo = logoImage(logoPath)
        async let plate: Void = backdropPlate(backdropPath)
        _ = await (logo, plate)
    }

    private static func logoImage(_ path: String?) async -> UIImage? {
        guard let url = TMDBClient.imageURL(path: path, size: "w500") else { return nil }
        return await ImageMemoryCache.load(url)
    }

    private static func backdropPlate(_ path: String?) async {
        guard let path else { return }
        await UltrablurPlates.warm(path)
    }
}
