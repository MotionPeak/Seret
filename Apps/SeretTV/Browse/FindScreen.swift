import DebridCore
import DebridUI
import SwiftUI

/// The single "get new content" surface: a Movies/Shows filter over the discover browse (search pill
/// + For You / Trending / … rails, from BrowseScreen). Folds the old Movies + TV pills into one; the
/// movie/show split is a light filter here, not two top-level destinations.
struct FindScreen: View {
    @State private var kind: MediaKind = .movie

    var body: some View {
        // The Movies/Shows filter rides at the START of BrowseScreen's search + segment row, so the
        // whole control set is one reachable row (the search pill + For You / Trending / … + rails
        // key off the selected kind).
        BrowseScreen(kind: kind) {
            Button("Movies") { kind = .movie }
                .buttonStyle(SeretPillStyle(selected: kind == .movie))
            Button("Shows") { kind = .show }
                .buttonStyle(SeretPillStyle(selected: kind == .show))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CanvasBackground())
    }
}
