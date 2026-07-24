import DebridCore
import DebridUI
import SwiftUI

/// The viewer's own 1–10 Trakt rating, as a focusable row of stars. Distinct from `RatingsRow`,
/// which shows the aggregate public scores (IMDb / Rotten Tomatoes / Metacritic). Hidden entirely
/// when Trakt isn't linked, so an unlinked Apple TV sees no dead control.
struct UserRatingRow: View {
    let store: DetailStore

    var body: some View {
        if store.canRate {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 16) {
                    Text("YOUR RATING")
                        .font(.caption.weight(.semibold)).kerning(1.5)
                        .foregroundStyle(Theme.Palette.gold)
                    if let rating = store.userRating {
                        Text("\(rating)/10")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.Palette.textSecondary)
                    }
                }
                // A focus section keeps the d-pad inside the star row until the viewer leaves it,
                // so gliding across stars doesn't jump out to a neighbouring control.
                HStack(spacing: 10) {
                    ForEach(1...10, id: \.self) { value in
                        Button {
                            Task { await store.rate(store.userRating == value ? nil : value) }
                        } label: {
                            Image(systemName: (store.userRating ?? 0) >= value ? "star.fill" : "star")
                                .font(.title3)
                                .foregroundStyle((store.userRating ?? 0) >= value
                                                 ? Theme.Palette.gold : Theme.Palette.textSecondary)
                        }
                        .buttonStyle(.card)
                        .accessibilityLabel("Rate \(value) out of 10")
                    }
                }
                .focusSection()
                Text("Select your current rating again to clear it.")
                    .font(.caption).foregroundStyle(Theme.Palette.textSecondary)
            }
            .task { await store.loadUserRating() }
        }
    }
}
