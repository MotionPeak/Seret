import DebridCore
import DebridUI
import SwiftUI

/// Movie Detail: backdrop, title + meta, quality chips, overview, Play/Resume, and Versions.
struct MovieDetail: View {
    let store: DetailStore
    private var item: MediaItem { store.item }
    private var contentKey: String { WatchKey.content(forMovie: item) }
    private var watch: WatchState? { store.watchState(forKey: contentKey) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(item.title).font(.largeTitle.bold())
                Text(metaLine).font(.subheadline).foregroundStyle(.secondary)
                if let best = store.bestSource { QualityChipRow(parsed: best.parsed) }
                if let overview = store.overview {
                    Text(overview).font(.callout).foregroundStyle(.secondary)
                }
                actions
                if store.versions.count > 1 { versionsSection }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .padding(.top, 220)
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
            HStack(spacing: 12) {
                if let resume = resumeSeconds {
                    NavigationLink(value: store.playRequest(source: best, episode: nil, label: item.title)) {
                        Label("Resume \(Timecode.format(resume))", systemImage: "play.fill")
                    }.buttonStyle(.borderedProminent)
                    NavigationLink(value: store.playRequest(source: best, episode: nil,
                                                            label: item.title, fromStart: true)) {
                        Label("Start", systemImage: "gobackward")
                    }.buttonStyle(.bordered)
                } else {
                    NavigationLink(value: store.playRequest(source: best, episode: nil, label: item.title)) {
                        Label("Play", systemImage: "play.fill")
                    }.buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private var versionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Versions").font(.headline)
            ForEach(store.versions, id: \.self) { src in
                NavigationLink(value: store.playRequest(source: src, episode: nil, label: item.title)) {
                    HStack {
                        QualityChipRow(parsed: src.parsed)
                        Spacer()
                        Image(systemName: "play.circle").foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
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
