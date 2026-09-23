import DebridUI
import SwiftUI

/// The rating/history column beside the overview (mockup 5's `.two`): ten stars for the viewer's
/// own 1–10 rating, then their history with the title. Hidden entirely when the title can't carry
/// a personal rating (`DetailStore.canRate`).
struct YourRating: View {
    let store: DetailStore

    @State private var hoveredStar: Int?

    var body: some View {
        if store.canRate {
            VStack(alignment: .leading, spacing: 10) {
                Text("YOUR RATING")
                    .font(Theme.Typo.label())
                    .tracking(1.5)
                    .foregroundStyle(Theme.Palette.gold)
                stars
                Text(store.userRating.map { "\($0)/10" } ?? "\u{2013}/10")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.Palette.textSecondary)
                historyLines
            }
            .frame(width: 300, alignment: .leading)
            .task {
                await store.loadUserRating()
                await store.loadWatchSummary()
            }
        }
    }

    private var stars: some View {
        HStack(spacing: 4) {
            ForEach(1...10, id: \.self) { n in
                Image(systemName: filled(n) ? "star.fill" : "star")
                    .font(.system(size: 16))
                    .foregroundStyle(filled(n) ? Theme.Palette.gold : Theme.Palette.textSecondary)
                    .onHover { isHovering in if isHovering { hoveredStar = n } }
                    .onTapGesture { rate(n) }
            }
        }
        .onHover { isHovering in if !isHovering { hoveredStar = nil } }
    }

    /// The hovered preview wins up to the hovered star; otherwise the stored rating.
    private func filled(_ n: Int) -> Bool {
        if let hoveredStar { return n <= hoveredStar }
        return (store.userRating ?? 0) >= n
    }

    private func rate(_ n: Int) {
        Task { await store.rate(RatingKey.next(current: store.userRating, pressed: n)) }
    }

    @ViewBuilder private var historyLines: some View {
        ForEach(TitlePageText.historyLines(summary: store.watchSummary, since: store.historySince), id: \.self) { line in
            Text(line)
                .font(.system(size: 12))
                .foregroundStyle(Theme.Palette.textSecondary)
        }
    }
}
