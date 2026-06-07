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
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .bottom) {
                AsyncImage(url: imageURL) { $0.resizable().aspectRatio(contentMode: .fill) }
                    placeholder: { Rectangle().fill(Theme.Palette.surface2) }
                    .frame(width: width, height: width * 9 / 16).clipped()
                GoldProgressBar(fraction: fraction).frame(width: width)
            }
            Text(title).font(.callout.weight(.semibold)).lineLimit(1)
                .frame(width: width, alignment: .leading)
            if !subtitle.isEmpty {
                Text(subtitle).font(.caption).foregroundStyle(Theme.Palette.textSecondary)
                    .lineLimit(1).frame(width: width, alignment: .leading)
            }
        }
    }
}

/// A titled horizontal rail. Content is a row of focusable cards.
struct HomeRail<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.title2.bold()).padding(.leading, 60)
            ScrollView(.horizontal) {
                LazyHStack(spacing: 40) { content }
                    .padding(.horizontal, 60).padding(.vertical, 40)
            }
            .scrollClipDisabled()
        }
    }
}
