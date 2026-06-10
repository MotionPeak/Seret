import DebridCore
import DebridUI
import SwiftUI

/// Thin gold progress capsule (resume fraction). Mirrors the iPhone/iPad GoldProgressBar.
struct GoldProgressBar: View {
    let fraction: Double
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.18))
                Capsule().fill(Theme.Palette.gold)
                    .frame(width: max(0, min(1, fraction)) * g.size.width)
                    .goldGlow(6, opacity: 0.7)
            }
        }
        .frame(height: 6)
    }
}

/// A 16:9 landscape card with resume progress — the focusable label inside a `.card` button.
struct LandscapeProgressCard: View {
    let title: String
    let subtitle: String
    let imageURL: URL?
    let fraction: Double
    var width: CGFloat = 460

    var body: some View {
        let height = width * 9 / 16
        return ZStack(alignment: .bottomLeading) {
            RemoteImage(url: imageURL)
                .frame(width: width, height: height)
            // Soft scrim only across the lower third, so the title reads without a hard grey bar.
            LinearGradient(colors: [.clear, .black.opacity(0.82)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.seret(Theme.Typography.cardSize, .semibold))
                    .foregroundStyle(.white).lineLimit(1)
                if !subtitle.isEmpty {
                    Text(subtitle).font(.seret(Theme.Typography.captionSize, .medium))
                        .foregroundStyle(.white.opacity(0.8)).lineLimit(1)
                }
            }
            .padding(.horizontal, 18).padding(.bottom, 18)
            GoldProgressBar(fraction: fraction).frame(width: width)   // pinned to the very bottom edge
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.posterCorner, style: .continuous))
    }
}

/// A titled horizontal rail. Content is a row of focusable cards.
struct HomeRail<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).sectionTitle().padding(.leading, Theme.Layout.contentMargin)
            ScrollView(.horizontal) {
                LazyHStack(spacing: 36) { content }
                    .padding(.horizontal, Theme.Layout.contentMargin).padding(.vertical, 40)
            }
            .scrollClipDisabled()
        }
    }
}
