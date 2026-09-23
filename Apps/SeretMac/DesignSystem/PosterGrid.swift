import SwiftUI

/// Fixed-width poster column math, pure so it can be unit-tested without measuring a real layout.
struct PosterGridLayout: Equatable {
    static let cardWidth: CGFloat = 150, spacing: CGFloat = 22, rowSpacing: CGFloat = 26

    let columns: Int
    private let cardWidth: CGFloat
    private let spacing: CGFloat

    init(availableWidth: CGFloat, cardWidth: CGFloat = Self.cardWidth, spacing: CGFloat = Self.spacing) {
        self.cardWidth = cardWidth
        self.spacing = spacing
        let raw = Int(((availableWidth + spacing) / (cardWidth + spacing)).rounded(.down))
        columns = max(1, raw)
    }

    var gridItems: [GridItem] {
        Array(repeating: GridItem(.fixed(cardWidth), spacing: spacing, alignment: .top), count: columns)
    }

    /// How many skeleton cards fill `rows` full rows at the current column count — so a loading
    /// grid holds the same height the real content will land at.
    func skeletonCount(rows: Int = 3) -> Int { columns * rows }
}

/// A grid of fixed-width poster cards that reflows its column count from the available width.
/// Loading shows card-sized shimmer skeletons — never a spinner — so the grid's height does not
/// jump when content lands. At least 12 pt of top padding so a lifted, hovered card's glow is
/// never clipped by the enclosing `ScrollView`.
///
/// Renders with `.adaptive` grid items (not `PosterGridLayout.gridItems`'s `.fixed` array):
/// `.fixed` columns declare a rigid ideal width of their own (`columns × cardWidth`), and inside a
/// `ScrollView` near a `WindowGroup` root that ideal width can OUTLIVE a later, smaller real
/// proposal — measured, on this window's actual open-then-settle resize (1440pt on first
/// appearance, then the restored 1200pt frame), as the grid permanently sticking at the column
/// count its first, wider pass computed. `.adaptive` has no such standing demand: it always lays
/// out from whatever width it is actually given, so it cannot get stuck. `PosterGridLayout` still
/// answers the column MATH (used for skeleton count and unit-tested on its own); the live grid
/// just does not use its `.fixed` `gridItems` to build the `LazyVGrid`.
struct PosterGrid<Item: Identifiable, Card: View>: View {
    let items: [Item]
    var isLoading: Bool = false
    /// Called from each card's `.onAppear` — a genre grid or search page uses it to trigger the
    /// next page shortly before the viewer reaches the bottom.
    var onItemAppear: (Item) -> Void = { _ in }
    @ViewBuilder let card: (Item) -> Card

    @State private var width: CGFloat = 0

    /// `.adaptive` with equal min/max: every column is exactly `cardWidth`, and the count self-
    /// adjusts to whatever width `LazyVGrid` is actually rendered at — no state, no feedback loop.
    private var adaptiveColumns: [GridItem] {
        [GridItem(.adaptive(minimum: PosterGridLayout.cardWidth, maximum: PosterGridLayout.cardWidth),
                 spacing: PosterGridLayout.spacing)]
    }

    var body: some View {
        LazyVGrid(columns: adaptiveColumns, alignment: .leading, spacing: PosterGridLayout.rowSpacing) {
            if isLoading {
                let count = PosterGridLayout(availableWidth: width).skeletonCount()
                ForEach(0..<count, id: \.self) { _ in skeletonCard }
            } else {
                ForEach(items) { item in
                    card(item).onAppear { onItemAppear(item) }
                }
            }
        }
        .padding(.top, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }

    private var skeletonCard: some View { CardSkeleton() }
}
