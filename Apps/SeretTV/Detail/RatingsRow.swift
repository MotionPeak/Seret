import DebridCore
import DebridUI
import SwiftUI

/// IMDb / Rotten Tomatoes / Metacritic badges from OMDb (tvOS). Renders only the scores that
/// exist; the whole row disappears when there are none (or ratings haven't loaded).
struct RatingsRow: View {
    let ratings: OMDbRatings?

    var body: some View {
        if let r = ratings, r.hasAny {
            HStack(spacing: 24) {
                if let imdb = r.imdb { Text("⭐ IMDb \(String(format: "%.1f", imdb))") }
                if let rt = r.rottenTomatoes { Text("🍅 \(rt)%") }
                if let mc = r.metacritic { Text("Ⓜ \(mc)") }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }
}
