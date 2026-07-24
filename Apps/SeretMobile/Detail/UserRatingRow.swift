import DebridCore
import DebridUI
import SwiftUI

/// The viewer's own 1–10 Trakt rating. Distinct from `RatingsRow`, which shows the aggregate
/// public scores (IMDb / Rotten Tomatoes / Metacritic). Hidden entirely when Trakt isn't linked.
struct UserRatingRow: View {
    let store: DetailStore

    var body: some View {
        if store.canRate {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                HStack(spacing: Theme.Space.sm) {
                    Text("YOUR RATING")
                        .font(.caption.weight(.semibold)).kerning(1)
                        .foregroundStyle(Theme.Palette.gold)
                    if let rating = store.userRating {
                        Text("\(rating)/10")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.Palette.textSecondary)
                        Button("Clear") { Task { await store.rate(nil) } }
                            .font(.caption).tint(Theme.Palette.textSecondary)
                    }
                }
                HStack(spacing: 6) {
                    ForEach(1...10, id: \.self) { value in
                        Button {
                            Task { await store.rate(value) }
                        } label: {
                            Image(systemName: (store.userRating ?? 0) >= value ? "star.fill" : "star")
                                .font(.title3)
                                .foregroundStyle((store.userRating ?? 0) >= value
                                                 ? Theme.Palette.gold : Theme.Palette.textSecondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Rate \(value) out of 10")
                    }
                }
            }
            .task { await store.loadUserRating() }
        }
    }
}
