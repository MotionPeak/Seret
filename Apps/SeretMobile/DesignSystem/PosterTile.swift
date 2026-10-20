import DebridCore
import SwiftUI

/// The rail and grid poster sizes, per size class — one place, so every rail on a page lines up
/// and a skeleton is exactly as tall as the row that replaces it.
enum PosterTileMetrics {
    /// About three tiles and a sliver across an iPhone (the mockup's 118pt); about five past the
    /// iPad sidebar.
    static func width(_ sizeClass: UserInterfaceSizeClass?) -> CGFloat {
        sizeClass == .regular ? 150 : 118
    }
    static func height(_ sizeClass: UserInterfaceSizeClass?) -> CGFloat { width(sizeClass) * 1.5 }
    static let spacing: CGFloat = 10
    static let corner: CGFloat = 12
    /// The page's leading text and first-tile edge.
    static func margin(_ sizeClass: UserInterfaceSizeClass?) -> CGFloat {
        sizeClass == .regular ? 40 : Theme.Space.xl
    }
    /// Adaptive grid columns at roughly the rail's tile size.
    static func gridColumns(_ sizeClass: UserInterfaceSizeClass?) -> [GridItem] {
        let minW: CGFloat = sizeClass == .regular ? 140 : 104
        let maxW: CGFloat = sizeClass == .regular ? 190 : 150
        return [GridItem(.adaptive(minimum: minW, maximum: maxW), spacing: PosterTileMetrics.spacing)]
    }
}

/// A rounded 2:3 poster with its marks ON the art, the way the mockups and the Apple TV draw it:
///
/// - `progress` — a white line inset along the foot (Continue Watching).
/// - `chip` — a small label at the top ("Next", "CAM", later "Both"); `chipTint` makes it a warning.
/// - `watched` dims the art and puts a white ✓ top-right; `owned` puts a quieter grey ✓ there
///   instead. Watched beats owned — having seen it is the more useful thing to know at a glance.
///
/// `width: nil` fills its grid column. No title under the art (the mockups' rails have none);
/// `showsTitle` adds one for search results, where the poster alone is not always enough.
/// With no artwork the title is set on a surface, never a blank block.
struct PosterTile: View {
    let posterPath: String?
    let title: String
    var width: CGFloat?
    var progress: Double?
    var chip: String?
    var chipTint: Color?
    var watched = false
    var owned = false
    var showsTitle = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            art
            if showsTitle {
                Text(title).font(Theme.Typo.caption())
                    .foregroundStyle(Theme.Palette.textSecondary).lineLimit(1)
            }
        }
        .frame(width: width)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var art: some View {
        Color.clear
            .aspectRatio(2.0 / 3.0, contentMode: .fit)
            .overlay {
                if let url = TMDBClient.imageURL(path: posterPath, size: "w342") {
                    RemoteImage(url: url) { noArt }
                } else {
                    noArt
                }
            }
            .overlay { if watched { Theme.Palette.artDim } }
            .overlay(alignment: .bottom) {
                if let progress, progress > 0 {
                    ProgressLine(fraction: progress, height: 3)
                        .padding(.horizontal, 8).padding(.bottom, 8)
                        .shadow(color: .black.opacity(0.5), radius: 3)
                }
            }
            .overlay(alignment: .top) {
                if let chip {
                    Text(chip)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(chipTint == nil ? Theme.Palette.textPrimary : .white)
                        .lineLimit(1)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(chipTint ?? Theme.Palette.surface1.opacity(0.88),
                                    in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .padding(.top, 7)
                }
            }
            .overlay(alignment: .topTrailing) {
                if watched || owned {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(watched ? Theme.Palette.focus : Theme.Palette.textSecondary)
                        .background(Circle().fill(Theme.Palette.badgeBacking))
                        .padding(6)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: PosterTileMetrics.corner, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: PosterTileMetrics.corner, style: .continuous)
                .stroke(Theme.Palette.hairline, lineWidth: 0.5))
    }

    private var noArt: some View {
        Theme.Palette.surface1
            .overlay {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(5)
                    .minimumScaleFactor(0.8)
                    .padding(10)
            }
    }

    private var accessibilityText: String {
        var parts = [title]
        if let chip { parts.append(chip) }
        if watched { parts.append("Watched") } else if owned { parts.append("In Library") }
        if let progress, progress > 0 { parts.append("\(Int((progress * 100).rounded()))% watched") }
        return parts.joined(separator: ", ")
    }
}

/// A row's last tile: its name and "See All" on glass, at the rail's poster size.
struct SeeAllTile: View {
    let title: String
    let width: CGFloat

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(Theme.Palette.textSecondary)
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.Palette.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.8)
            Text("See All")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.Palette.textSecondary)
        }
        .padding(12)
        .frame(width: width, height: width * 1.5)
        .seretGlass(in: RoundedRectangle(cornerRadius: PosterTileMetrics.corner, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("See all \(title)")
    }
}

/// A titled row of posters that scrolls sideways and settles on a tile edge, with a quiet
/// "See All" in its header when `seeAll` names somewhere to go (a `NavigationLink` value — the page
/// registers the destination).
struct PosterRail<Content: View, Route: Hashable>: View {
    let title: String
    var seeAll: Route?
    /// Quiet words after the title ("ready to play").
    var subtitle: String? = nil
    @ViewBuilder var content: Content
    @Environment(\.horizontalSizeClass) private var hSize

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            RailHeader(title: title, seeAll: seeAll, subtitle: subtitle)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: PosterTileMetrics.spacing) { content }
                    .scrollTargetLayout()
            }
            .contentMargins(.horizontal, PosterTileMetrics.margin(hSize), for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            // Holds the row's height from its first frame, so a row whose tiles are still being
            // laid out never collapses and jumps the page.
            .frame(minHeight: PosterTileMetrics.height(hSize))
        }
    }
}

extension PosterRail where Route == Never {
    init(title: String, @ViewBuilder content: () -> Content) {
        self.init(title: title, seeAll: nil, content: content)
    }
}

/// A rail's heading: bold title-case white, with "See All" on the right when there is a grid.
struct RailHeader<Route: Hashable>: View {
    let title: String
    var seeAll: Route?
    var subtitle: String? = nil
    @Environment(\.horizontalSizeClass) private var hSize

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.md) {
            Text(title).font(Theme.Typo.railTitle())
                .foregroundStyle(Theme.Palette.textPrimary)
                .lineLimit(2)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .lineLimit(1)
                    .layoutPriority(-1)
            }
            Spacer(minLength: 0)
            if let seeAll {
                NavigationLink(value: seeAll) {
                    Text("See All")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .fixedSize()
                }
                .accessibilityLabel("See all \(title)")
            }
        }
        .padding(.horizontal, PosterTileMetrics.margin(hSize))
    }
}

/// Loading rows at the real rail metrics, so the first row lands exactly where its skeleton was.
struct RailSkeleton: View {
    var rows = 2
    @Environment(\.horizontalSizeClass) private var hSize

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            ForEach(0..<rows, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 10) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Theme.Palette.surface2)
                        .frame(width: 180, height: 22)
                    HStack(spacing: PosterTileMetrics.spacing) {
                        ForEach(0..<8, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: PosterTileMetrics.corner, style: .continuous)
                                .fill(Theme.Palette.surface1)
                                .frame(width: PosterTileMetrics.width(hSize),
                                       height: PosterTileMetrics.height(hSize))
                        }
                    }
                }
                .padding(.leading, PosterTileMetrics.margin(hSize))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
        .accessibilityHidden(true)
    }
}
