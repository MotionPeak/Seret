import DebridCore
import DebridUI
import SwiftUI

/// The single "get new content" surface: a Movies/Shows filter over the discover browse (search pill
/// + For You / Trending / … rails, from BrowseScreen). Folds the old Movies + TV pills into one; the
/// movie/show split is a light filter here, not two top-level destinations.
struct FindScreen: View {
    @State private var kind: MediaKind = .movie

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            kindFilter
                .padding(.leading, 60)
                .padding(.top, 8)
                .padding(.bottom, 4)
            BrowseScreen(kind: kind)   // search + discover segments + rails, keyed to the kind
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CanvasBackground())
    }

    private var kindFilter: some View {
        HStack(spacing: 12) {
            Button("Movies") { kind = .movie }
                .buttonStyle(SeretPillStyle(selected: kind == .movie))
            Button("Shows") { kind = .show }
                .buttonStyle(SeretPillStyle(selected: kind == .show))
        }
    }
}
