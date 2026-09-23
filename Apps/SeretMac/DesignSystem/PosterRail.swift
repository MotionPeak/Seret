import SwiftUI

/// Horizontal paging for a rail: a page is 85% of the viewport, clamped to the content. Pure so the
/// maths is unit-tested without a real `ScrollView`.
enum RailPager {
    enum Direction { case back, forward }

    static func target(offset: CGFloat, viewport: CGFloat, content: CGFloat, _ direction: Direction) -> CGFloat {
        let page = viewport * 0.85
        let maxOffset = max(0, content - viewport)
        switch direction {
        case .forward: return min(maxOffset, offset + page)
        case .back: return max(0, offset - page)
        }
    }

    /// 1 pt slack so a rail that has landed exactly at an end does not keep offering to page
    /// further in that direction.
    static func canPage(offset: CGFloat, viewport: CGFloat, content: CGFloat, _ direction: Direction) -> Bool {
        let maxOffset = max(0, content - viewport)
        switch direction {
        case .forward: return offset < maxOffset - 1
        case .back: return offset > 1
        }
    }
}

/// What a rail's `ScrollView` reports right now, so the pager buttons know whether — and how far —
/// to page.
struct RailGeometry: Equatable {
    var offset: CGFloat = 0
    var viewport: CGFloat = 0
    var content: CGFloat = 0
}

/// A full-bleed horizontal rail: a gold label, then cards a mouse wheel cannot scroll sideways, so
/// glass ‹ › pager buttons appear on hover. `.contentMargins`/`.scrollClipDisabled()` and 20 pt
/// vertical inner padding keep a tilted, lifted, glowing card from ever being clipped.
struct PosterRail<Item: Identifiable, Card: View>: View {
    let title: String
    let items: [Item]
    var cardHeight: CGFloat = PosterCard.posterSize.height
    /// Harness-only: forces the pager chevrons on so they can be screenshotted without a pointer.
    var previewShowsPager = false
    @ViewBuilder let card: (Item) -> Card

    @Environment(\.pageLeadingInset) private var pageLeadingInset
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var geometry = RailGeometry()
    @State private var position: ScrollPosition = ScrollPosition()
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(Theme.Typo.label())
                .tracking(1.5)
                .foregroundStyle(Theme.Palette.gold)
                .padding(.leading, pageLeadingInset)
            ZStack {
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: PosterGridLayout.spacing) {
                        ForEach(items) { card($0) }
                    }
                    .padding(.vertical, 20)
                }
                .contentMargins(.leading, pageLeadingInset, for: .scrollContent)
                .contentMargins(.trailing, 28, for: .scrollContent)
                .scrollClipDisabled()
                .scrollIndicators(.hidden)
                .scrollPosition($position)
                .onScrollGeometryChange(for: RailGeometry.self) { geo in
                    RailGeometry(offset: geo.contentOffset.x, viewport: geo.containerSize.width,
                                content: geo.contentSize.width)
                } action: { _, new in
                    geometry = new
                }
                pagerOverlay
            }
        }
        .onHover { isHovered = $0 }
    }

    private var showsPager: Bool { isHovered || previewShowsPager }

    private var pagerOverlay: some View {
        HStack {
            pagerButton(.back, symbol: "chevron.left")
                .padding(.leading, max(0, pageLeadingInset - 18))
            Spacer(minLength: 0)
            pagerButton(.forward, symbol: "chevron.right")
                .padding(.trailing, 10)
        }
        .allowsHitTesting(showsPager)
    }

    @ViewBuilder private func pagerButton(_ direction: RailPager.Direction, symbol: String) -> some View {
        let canPage = RailPager.canPage(offset: geometry.offset, viewport: geometry.viewport,
                                        content: geometry.content, direction)
        if canPage {
            Button {
                let target = RailPager.target(offset: geometry.offset, viewport: geometry.viewport,
                                              content: geometry.content, direction)
                if reduceMotion {
                    position.scrollTo(x: target)
                } else {
                    withAnimation(Theme.Motion.standard) { position.scrollTo(x: target) }
                }
            } label: {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .frame(width: 36, height: 36)
                    .glassEffect(.regular.interactive(), in: Circle())
            }
            .buttonStyle(.plain)
            .opacity(showsPager ? 1 : 0)
            .animation(Theme.Motion.quick, value: showsPager)
        }
    }
}

/// A rail's loading state: a shimmer title bar, then `count` card-sized shimmers — same paddings
/// as `PosterRail`, so a rail's height never changes between skeleton and content.
struct RailSkeleton: View {
    var cardSize: CGSize = PosterCard.posterSize
    var count: Int = 7

    @Environment(\.pageLeadingInset) private var pageLeadingInset

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ShimmerView(cornerRadius: 4).frame(width: 160, height: 12)
                .padding(.leading, pageLeadingInset)
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: PosterGridLayout.spacing) {
                    ForEach(0..<count, id: \.self) { _ in skeletonCard }
                }
                .padding(.vertical, 20)
            }
            .contentMargins(.leading, pageLeadingInset, for: .scrollContent)
            .contentMargins(.trailing, 28, for: .scrollContent)
            .scrollClipDisabled()
            .scrollIndicators(.hidden)
            .scrollDisabled(true)
        }
    }

    private var skeletonCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            ShimmerView().frame(width: cardSize.width, height: cardSize.height)
            ShimmerView(cornerRadius: 4).frame(width: 110, height: 12)
        }
    }
}
