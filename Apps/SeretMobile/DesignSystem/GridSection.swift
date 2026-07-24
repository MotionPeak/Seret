import SwiftUI

/// A titled vertical poster grid — the counterpart to `Rail`.
///
/// Use `Rail` for a short, ordered queue you flick through (Continue Watching); use this for a
/// section meant to be browsed as a wall, where a side-scroller hides most of the content.
struct GridSection<Content: View>: View {
    let title: String
    var onSeeAll: (() -> Void)? = nil
    @ViewBuilder var content: Content
    @Environment(\.horizontalSizeClass) private var hSize

    /// Matches `LibraryGrid`'s adaptive sizing so Home and My Library read as the same shelf
    /// (~3 columns on iPhone, ~5 on iPad).
    private var columns: [GridItem] {
        let minW: CGFloat = hSize == .regular ? 158 : 110
        let maxW: CGFloat = hSize == .regular ? 220 : 170
        return [GridItem(.adaptive(minimum: minW, maximum: maxW), spacing: Theme.Space.lg)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            SectionHeader(title: title, action: onSeeAll)
            // No inner ScrollView: this sits inside Home's vertical ScrollView, so the grid just
            // grows and the page scrolls as one.
            LazyVGrid(columns: columns, alignment: .leading, spacing: Theme.Space.xl) {
                content
            }
            .padding(.horizontal, Theme.Space.lg)
        }
    }
}
