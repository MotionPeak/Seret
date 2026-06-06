import DebridCore
import DebridUI
import SwiftUI

/// Movie Detail: backdrop, title + meta, quality chips, Play/Resume, overview, and Versions.
struct MovieDetail: View {
    let store: DetailStore
    private var item: MediaItem { store.item }
    private var contentKey: String { WatchKey.content(forMovie: item) }
    private var watch: WatchState? { store.watchState(forKey: contentKey) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.lg) {
                Text(item.title).font(Theme.Typo.titleXL()).foregroundStyle(Theme.Palette.textPrimary)
                Text(metaLine).font(Theme.Typo.body()).foregroundStyle(Theme.Palette.textSecondary)
                if let best = store.bestSource { QualityChipRow(parsed: best.parsed) }
                actions
                if let overview = store.overview {
                    Text(overview).font(Theme.Typo.body())
                        .foregroundStyle(Theme.Palette.textSecondary).lineSpacing(3)
                }
                if store.versions.count > 1 { versionsSection }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Space.lg)
            .padding(.top, 200)
        }
        .background(DetailBackdrop(path: store.backdropPath, posterFallback: item.posterPath))
        .navigationTitle(item.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var metaLine: String {
        var parts: [String] = []
        if let y = item.year { parts.append(String(y)) }
        if let r = store.runtime { parts.append("\(r) min") }
        if !store.genres.isEmpty { parts.append(store.genres.prefix(3).joined(separator: " · ")) }
        return parts.joined(separator: "  ·  ")
    }

    @ViewBuilder private var actions: some View {
        if let best = store.bestSource {
            HStack(spacing: Theme.Space.md) {
                if let resume = resumeSeconds {
                    NavigationLink(value: store.playRequest(source: best, episode: nil, label: item.title)) {
                        Label("Resume · \(Timecode.format(resume))", systemImage: "play.fill")
                    }.buttonStyle(GoldButtonStyle())
                    NavigationLink(value: store.playRequest(source: best, episode: nil,
                                                            label: item.title, fromStart: true)) {
                        Label("Start", systemImage: "gobackward")
                    }.buttonStyle(GhostButtonStyle())
                } else {
                    NavigationLink(value: store.playRequest(source: best, episode: nil, label: item.title)) {
                        Label("Play", systemImage: "play.fill")
                    }.buttonStyle(GoldButtonStyle())
                }
            }
        }
    }

    private var versionsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text("VERSIONS").font(Theme.Typo.label()).tracking(1.5).foregroundStyle(Theme.Palette.gold)
            ForEach(store.versions, id: \.self) { src in
                NavigationLink(value: store.playRequest(source: src, episode: nil, label: item.title)) {
                    HStack {
                        QualityChipRow(parsed: src.parsed)
                        Spacer()
                        Image(systemName: "play.circle.fill").foregroundStyle(Theme.Palette.gold)
                    }
                    .padding(Theme.Space.md)
                    .background(Theme.Palette.surface2, in: RoundedRectangle(cornerRadius: Theme.Radius.chip))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var resumeSeconds: Double? {
        guard let w = watch, !w.finished, w.positionSeconds > 0 else { return nil }
        return w.positionSeconds
    }
}
