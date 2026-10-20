import DebridCore
import DebridUI
import SwiftUI

/// The horizontally scrolling genre selector at the top of Movies/Shows. `All` keeps the segment
/// rails; any other pill swaps the page for that genre's grid.
///
/// Commit-on-press, like every other pill row in the app: focusing a genre only highlights it. A
/// switch-on-focus row here would fire a TMDB request on every glide of the remote.
///
/// Inside a `FocusBrowsePage` each pill is named for the page's focus (`focusID(for:)`) and reports
/// focus to its row, so the page can return to it and scroll the row into place; anywhere else
/// those hooks do nothing.
struct GenreStrip: View {
    let kind: MediaKind
    /// nil = "All".
    @Binding var selection: DiscoverStore.Genre?
    /// Where the first pill starts — the row itself runs edge to edge, so a focused, scaled pill
    /// is never clipped at either end.
    var leadingInset: CGFloat = FocusBrowseLayout.leadingInset
    /// Make the selected pill this strip's default focus — for the genre grid, whose strip
    /// replaces the page's one under a focused pill and must catch that focus.
    var claimsFocus = false

    @FocusState private var focused: Int?
    /// The claim is made once, when the strip arrives. `.task` runs again on every re-appearance —
    /// coming back from a title opened in the grid — and re-claiming then pulled focus off the
    /// poster the viewer came back to and onto the genre pill.
    @State private var claimed = false
    /// The claim is over: focus reached the asked-for pill, or the side menu has it. From then on
    /// the viewer is driving, and a late write pulled focus back out from under them — Left into
    /// the menu right after the grid opened was undone by the claim's next retry. (Focus on ANOTHER
    /// pill does not end it: that is the re-home to "All" the claim is there to correct.)
    @State private var claimSettled = false
    /// Set by the shell: the side menu has focus.
    @Environment(\.sideMenuHoldsFocus) private var sideMenuHoldsFocus

    /// The page focus id of the pill for `genre` (nil = All).
    static func focusID(for genre: DiscoverStore.Genre?) -> String { "genre/\(genre?.tmdbID ?? 0)" }

    var body: some View {
        // `claimsFocus` is fixed for a strip's life, so this is never a swap under focus.
        if claimsFocus {
            strip
                .defaultFocus($focused, selection?.tmdbID ?? 0, priority: .userInitiated)
                // The default alone is not enough when this strip arrives under a focus that just
                // vanished: measured, tvOS re-homed to the top-leading pill ("All") instead. So it
                // is also asked for, until it takes (the first writes can land before the strip is
                // in the focus tree) — or until the viewer has moved on (`claimSettled`). Measured
                // in the signed-in app: the menu never takes focus during the swap, so stopping
                // when it has focus costs the claim nothing.
                .task { await claimFocus() }
                .onChange(of: focused) { _, now in
                    if now == (selection?.tmdbID ?? 0) { claimSettled = true }
                }
                .onChange(of: sideMenuHoldsFocus) { _, inMenu in if inMenu { claimSettled = true } }
        } else {
            strip
        }
    }

    private var strip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                pill("All", genre: nil)
                ForEach(DiscoverStore.genres(for: kind)) { genre in
                    pill(genre.name, genre: genre)
                }
            }
            .padding(.horizontal, leadingInset)
            .padding(.vertical, 12)
        }
        .scrollClipDisabled()
        // Full width BEFORE the section, so a poster scrolled far right still has this row above it.
        .frame(maxWidth: .infinity, alignment: .leading)
        .focusSection()
    }

    private func claimFocus() async {
        guard !claimed else { return }
        claimed = true
        let target = selection?.tmdbID ?? 0
        for _ in 0..<10 {
            if claimSettled || sideMenuHoldsFocus || focused == target { return }
            focused = target
            try? await Task.sleep(for: .milliseconds(60))
            if Task.isCancelled { return }
        }
    }

    private func pill(_ title: String, genre: DiscoverStore.Genre?) -> some View {
        Button(title) { selection = genre }
            .buttonStyle(SeretPillStyle(selected: selection == genre))
            .focused($focused, equals: genre?.tmdbID ?? 0)
            .plexFocusID(Self.focusID(for: genre))
            .reportsPlexRailFocus()
    }
}
