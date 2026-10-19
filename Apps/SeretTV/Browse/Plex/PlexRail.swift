import SwiftUI

/// One horizontal rail of a `FocusBrowsePage`: a 34pt title at the page's leading inset over a
/// lazy row of tiles.
///
/// - The row scrolls edge to edge with clipping off, so a focused tile's 1.08 lift and ring are
///   never cut at the row's ends; the vertical padding is the room for that lift.
/// - Full-width frame FIRST, then `.focusSection()` — a section only catches a directional move
///   when its frame intersects the direction of travel, so a shrink-wrapped row would leave the
///   outer tiles of the rail above with nothing below them (CLAUDE.md, `.focusSection()`).
/// - `id` is the rail's stable identity: the page scrolls to it when focus enters the rail.
///   Never branch skeleton ↔ real INSIDE `content` with overlapping ids — branch around the rail.
struct PlexRail<Content: View>: View {
    let title: String
    let id: String
    @ViewBuilder var content: Content

    init(title: String, id: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.id = id
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(title)
                .sectionTitle()
                .foregroundStyle(Theme.Palette.textPrimary)
                .lineLimit(1)
                .padding(.leading, FocusBrowseLayout.leadingInset)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 28) { content }
                    .padding(.horizontal, FocusBrowseLayout.leadingInset)
            }
            .scrollClipDisabled()
        }
        .padding(.vertical, FocusBrowseLayout.railVerticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .focusSection()
        .plexBrowseRow(id: id)
    }
}

// MARK: - Rail focus reporting

extension View {
    /// Marks this view as one row of a `FocusBrowsePage` (a `PlexRail` does it for itself): the
    /// page scrolls the row to the top of the rail area whenever focus enters it. Use it on a
    /// row that is not a `PlexRail` — a pill strip, a genre strip — so moving back into it still
    /// moves the page.
    func plexBrowseRow(id: String) -> some View {
        modifier(PlexBrowseRowModifier(id: id))
    }

    /// Reports focus entering this tile to its row (see `plexBrowseRow(id:)`), and calls
    /// `onFocus`. `PosterTile` does this itself; any other focusable tile in a rail must too.
    func reportsPlexRailFocus(_ onFocus: @escaping () -> Void = {}) -> some View {
        modifier(PlexRailFocusReporter(onFocus: onFocus))
    }
}

private struct PlexBrowseRowModifier: ViewModifier {
    let id: String
    @Environment(\.focusBrowseRowFocused) private var pageReport

    func body(content: Content) -> some View {
        let id = id
        let pageReport = pageReport
        content
            .environment(\.plexRowDidFocus, { pageReport(id) })
            .id(id)
    }
}

private struct PlexRailFocusReporter: ViewModifier {
    let onFocus: () -> Void
    @Environment(\.plexRowDidFocus) private var rowReport
    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        content
            .focused($focused)
            .onChange(of: focused) { _, now in
                guard now else { return }
                onFocus()
                rowReport()
            }
    }
}

/// A row's "focus entered me" call, set by `plexBrowseRow(id:)`. A no-op default, so a tile
/// outside any browse page does nothing rather than trapping.
private struct PlexRowDidFocusKey: EnvironmentKey {
    static let defaultValue: @MainActor () -> Void = {}
}

/// The page's "focus entered row `id`" call, set by `FocusBrowsePage`.
private struct FocusBrowseRowFocusedKey: EnvironmentKey {
    static let defaultValue: @MainActor (String) -> Void = { _ in }
}

extension EnvironmentValues {
    fileprivate var plexRowDidFocus: @MainActor () -> Void {
        get { self[PlexRowDidFocusKey.self] }
        set { self[PlexRowDidFocusKey.self] = newValue }
    }

    var focusBrowseRowFocused: @MainActor (String) -> Void {
        get { self[FocusBrowseRowFocusedKey.self] }
        set { self[FocusBrowseRowFocusedKey.self] = newValue }
    }
}
