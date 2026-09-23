import DebridCore
import DebridUI
import SwiftUI

/// Home's full-bleed hero: the latest Continue Watching entry, its backdrop drifting (mockup 3's
/// Ken Burns), the title as large text, and Resume + Details. Resume plays directly through the
/// player slot when the entry's file resolved; otherwise — and for Details, and a click anywhere
/// on the artwork — it opens the title page. Mirrors `TitleHero`'s structure over the same
/// `HeroBackdrop`, but the whole backdrop is itself the "open" button (Decision: artwork opens
/// the title too), with Resume/Details overlaid on top exactly as `PosterTile` overlays its quick
/// actions on its own open-button.
struct HomeHero: View {
    let entry: HomeItem

    @Environment(ShellModel.self) private var shell: ShellModel?
    @Environment(\.pageLeadingInset) private var pageLeadingInset
    @State private var width: CGFloat = 1200

    private var height: CGFloat { TitlePageLayout.heroHeight(width: width) }

    var body: some View {
        Button(action: openTitle) {
            HeroBackdrop(url: TMDBClient.imageURL(path: entry.item.backdropPath ?? entry.item.posterPath, size: "w1280"),
                        drifts: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: height)
        .overlay(alignment: .bottomLeading) { copy }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .clipped()
        .contextMenu { menuContent }
    }

    private var copy: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(eyebrow.uppercased())
                .font(Theme.Typo.label())
                .tracking(1.5)
                .foregroundStyle(Theme.Palette.gold)
            Text(entry.item.title)
                .font(.system(size: 44, weight: .heavy))
                .foregroundStyle(Theme.Palette.textPrimary)
                .lineLimit(2)
                .shadow(color: .black.opacity(0.6), radius: 12, y: 4)
            actions
        }
        .padding(.leading, pageLeadingInset + 8)
        .padding(.bottom, 40)
        .frame(maxWidth: 640, alignment: .leading)
    }

    private var eyebrow: String {
        ContinueCaption.eyebrow(kind: entry.item.kind, subtitle: entry.subtitle,
                                resumeAt: entry.resumeAt, fraction: entry.fraction)
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button(action: resume) {
                Label(entry.isResumable ? "Resume" : "Open", systemImage: "play.fill")
            }
            .buttonStyle(GoldButtonStyle())
            Button(action: openTitle) {
                Label("Details", systemImage: "info.circle")
            }
            .buttonStyle(GlassButtonStyle())
        }
        .padding(.top, 4)
    }

    @ViewBuilder private var menuContent: some View {
        Button(action: resume) { Label(entry.isResumable ? "Resume" : "Open", systemImage: "play.fill") }
        Button(action: openTitle) { Label("Details", systemImage: "info.circle") }
    }

    private func resume() {
        if let request = entry.playbackRequest() {
            shell?.present(request)
        } else {
            openTitle()
        }
    }

    private func openTitle() {
        shell?.open(.title(entry.item))
    }
}
