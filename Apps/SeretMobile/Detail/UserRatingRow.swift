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
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                HStack(spacing: Theme.Space.sm) {
                    Text("YOUR RATING")
                        .font(.caption.weight(.semibold)).kerning(1)
                        .foregroundStyle(Theme.Palette.textSecondary)
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
