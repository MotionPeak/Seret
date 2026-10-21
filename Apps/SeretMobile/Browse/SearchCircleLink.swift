import DebridCore
import SwiftUI

/// The glass Search circle on a root page's header (Home, Movies, Shows): pushes the Search page
/// onto that page's own stack, so the tab keeps its place when you come back.
///
/// iPhone only. On iPad the sidebar has its own Search row, and a second way in on every page
/// header only crowded the art.
struct SearchCircleLink: View {
    var kind: MediaKind = .movie
    @Environment(\.horizontalSizeClass) private var hSize

    var body: some View {
        if hSize != .regular {
            NavigationLink {
                FindScreen(kind: kind)
            } label: {
                GlassCircleLabel(systemImage: "magnifyingglass")
            }
            .buttonStyle(GlassPressStyle())
            .accessibilityLabel("Search")
        }
    }
}
