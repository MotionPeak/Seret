import DebridCore
import DebridUI
import SwiftUI

/// The viewer's own 1–10 rating. Distinct from `RatingsRow`, which shows the aggregate
/// public scores (IMDb / Rotten Tomatoes / Metacritic). Hidden entirely when there is no watch store.
struct UserRatingRow: View {
    let store: DetailStore
    /// The star size follows Dynamic Type, but only so far: ten stars at an accessibility text size
    /// were wider than the screen, and because this row sits in the page's VStack it widened the
    /// WHOLE title page — clipping the text and pushing the episode play buttons off-screen.
    @ScaledMetric(relativeTo: .title3) private var starSize: CGFloat = 22
    private static let maxStarSize: CGFloat = 30

    var body: some View {
        if store.canRate {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                TitleSectionHeader(title: "Your Rating") {
                    if let rating = store.userRating {
                        HStack(spacing: Theme.Space.md) {
                            Text("\(rating)/10")
                                .font(.system(size: 15, weight: .semibold).monospacedDigit())
                                .foregroundStyle(Theme.Palette.textPrimary)
                            Button("Clear") { Task { await store.rate(nil) } }
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Theme.Palette.textSecondary)
                        }
                    }
                }
                HStack(spacing: 8) {
                    ForEach(1...10, id: \.self) { value in
                        Button {
                            Task { await store.rate(value) }
                        } label: {
                            // Resizable with no minimum: the stars shrink to share whatever width
                            // the row is given rather than dictate it.
                            Image(systemName: (store.userRating ?? 0) >= value ? "star.fill" : "star")
                                .resizable().scaledToFit()
                                .frame(maxWidth: min(starSize, Self.maxStarSize),
                                       maxHeight: min(starSize, Self.maxStarSize))
                                .foregroundStyle((store.userRating ?? 0) >= value
                                                 ? Theme.Palette.focus : Theme.Palette.textSecondary)
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
