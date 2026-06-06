import SwiftUI

/// A titled horizontal scroller. Pass cards (e.g. PosterCard) as content.
struct Rail<Content: View>: View {
    let title: String
    var onSeeAll: (() -> Void)? = nil
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            SectionHeader(title: title, action: onSeeAll)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: Theme.Space.md) { content }
                    .padding(.horizontal, Theme.Space.lg)
            }
        }
    }
}
