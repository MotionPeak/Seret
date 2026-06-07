import DebridCore
import DebridUI
import SwiftUI

/// Movie Detail: backdrop, title + meta, quality chips, Play/Resume, overview, and Versions.
struct MovieDetail: View {
    let store: DetailStore
    let onPlay: (PlaybackRequest) -> Void
    /// Per-version remove (one MediaSource → one RD torrent). Owner-injected; nil hides the
    /// affordance.
    var onRemoveVersion: ((MediaSource) -> Void)? = nil
    private var item: MediaItem { store.item }
    private var contentKey: String { WatchKey.content(forMovie: item) }
    private var watch: WatchState? { store.watchState(forKey: contentKey) }
    @State private var pendingVersionRemoval: MediaSource?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.lg) {
                Text(item.title).font(Theme.Typo.titleXL()).foregroundStyle(Theme.Palette.textPrimary)
                Text(metaLine).font(Theme.Typo.body()).foregroundStyle(Theme.Palette.textSecondary)
                if let best = store.bestSource { QualityChipRow(parsed: best.parsed) }
                actions
                if store.bestSource == nil, let tmdb = item.tmdbID {
                    MovieDownloadSection(tmdbID: tmdb, title: item.title, posterPath: item.posterPath,
                                         imdbID: store.imdbID, originalLanguage: store.originalLanguage)
                }
                if let overview = store.overview {
                    Text(overview).font(Theme.Typo.body())
                        .foregroundStyle(Theme.Palette.textSecondary).lineSpacing(3)
                }
                if !store.versions.isEmpty { versionsSection }
            }
            .frame(maxWidth: 700, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Theme.Space.lg)
            .padding(.top, 200)
            .padding(.bottom, Theme.Space.xxl)
        }
        .background(DetailBackdrop(path: store.backdropPath, posterFallback: item.posterPath))
        .navigationTitle(item.title)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Remove this version?",
            isPresented: Binding(get: { pendingVersionRemoval != nil },
                                 set: { if !$0 { pendingVersionRemoval = nil } }),
            titleVisibility: .visible,
            presenting: pendingVersionRemoval) { src in
                Button("Remove", role: .destructive) {
                    if let onRemoveVersion { onRemoveVersion(src) }
                    pendingVersionRemoval = nil
                }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("This deletes just this version from your Real\u{2011}Debrid account.")
            }
    }

    private var metaLine: String {
        var parts: [String] = []
        if let y = item.year { parts.append(String(y)) }
        if let r = store.runtime { parts.append("\(r) min") }
        if !store.genres.isEmpty { parts.append(store.genres.prefix(3).joined(separator: " · ")) }
        return parts.joined(separator: "  ·  ")
    }

    @ViewBuilder private var actions: some View {
        HStack(spacing: Theme.Space.md) {
            if let best = store.bestSource {
                if let resume = resumeSeconds {
                    Button { onPlay(store.playRequest(source: best, episode: nil, label: item.title)) } label: {
                        Label("Resume · \(Timecode.format(resume))", systemImage: "play.fill")
                    }.buttonStyle(GoldButtonStyle())
                    Button { onPlay(store.playRequest(source: best, episode: nil, label: item.title, fromStart: true)) } label: {
                        Label("Start", systemImage: "gobackward")
                    }.buttonStyle(GhostButtonStyle())
                } else {
                    Button { onPlay(store.playRequest(source: best, episode: nil, label: item.title)) } label: {
                        Label("Play", systemImage: "play.fill")
                    }.buttonStyle(GoldButtonStyle())
                }
            }
            TrailerButton(tmdbID: item.tmdbID, kind: .movie)
        }
    }

    private var versionsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text("VERSIONS").font(Theme.Typo.label()).tracking(1.5).foregroundStyle(Theme.Palette.gold)
            ForEach(store.versions, id: \.self) { src in versionRow(src) }
        }
    }

    private func versionRow(_ src: MediaSource) -> some View {
        HStack {
            Button { onPlay(store.playRequest(source: src, episode: nil, label: item.title)) } label: {
                HStack {
                    QualityChipRow(parsed: src.parsed)
                    Spacer()
                    Image(systemName: "play.circle.fill").foregroundStyle(Theme.Palette.gold)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if onRemoveVersion != nil {
                Menu {
                    Button("Remove this version", systemImage: "trash", role: .destructive) {
                        pendingVersionRemoval = src
                    }
                } label: {
                    Image(systemName: "ellipsis").foregroundStyle(Theme.Palette.textSecondary)
                        .padding(.leading, Theme.Space.sm)
                        .frame(minWidth: 30, minHeight: 30)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
            }
        }
        .padding(Theme.Space.md)
        .background(Theme.Palette.surface2, in: RoundedRectangle(cornerRadius: Theme.Radius.chip))
    }

    private var resumeSeconds: Double? {
        guard let w = watch, !w.finished, w.positionSeconds > 0 else { return nil }
        return w.positionSeconds
    }
}

/// Request Download for a movie with no cached/playable version — the Detail-screen sibling of the
/// Add flow's section. Fetches the best uncached release via the shared Add seam and starts an RD
/// download, then shows live progress from the app-wide `DownloadStore`. When it finishes, the
/// title flips into the library and Play lights up.
private struct MovieDownloadSection: View {
    let tmdbID: Int
    let title: String
    let posterPath: String?
    let imdbID: String?
    let originalLanguage: String?
    @Environment(AppSession.self) private var session
    @State private var requesting = false

    var body: some View {
        let status = session.downloadStore?.status(forTMDB: tmdbID)
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            if requesting && status == nil {
                ProgressView("Starting download…").tint(Theme.Palette.gold)
            } else if case .queued = status?.phase {
                ProgressView("Starting download…").tint(Theme.Palette.gold)
            } else if case .downloading = status?.phase {
                let pct = Int((status?.fraction ?? 0) * 100)
                Label("Downloading \(pct)% to Real‑Debrid…", systemImage: "arrow.down.circle.fill")
                    .font(Theme.Typo.body()).foregroundStyle(Theme.Palette.gold)
                ProgressView(value: status?.fraction ?? 0).tint(Theme.Palette.gold)
                Text("It'll appear here when it's ready.")
                    .font(Theme.Typo.caption()).foregroundStyle(Theme.Palette.textTertiary)
            } else if case .failed(let reason) = status?.phase {
                Label(reason, systemImage: "exclamationmark.triangle")
                    .font(Theme.Typo.body()).foregroundStyle(.orange)
                requestButton("Try Another Version")
            } else {
                Label("Not in your library yet", systemImage: "arrow.down.circle")
                    .font(Theme.Typo.body()).foregroundStyle(Theme.Palette.textSecondary)
                Text("No cached version exists. Start a download and it'll appear here when it's ready.")
                    .font(Theme.Typo.caption()).foregroundStyle(Theme.Palette.textTertiary)
                requestButton("Request Download")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func requestButton(_ label: String) -> some View {
        Button {
            Task {
                requesting = true
                var candidates: [CachedStream] = []
                if let imdbID, let add = session.makeAddStore(imdbID: imdbID, kind: .movie,
                                                              originalLanguage: originalLanguage) {
                    candidates = await add.uncachedCandidates()
                }
                await session.downloadStore?.request(tmdbID: tmdbID, title: title, kind: .movie,
                                                     candidates: candidates, posterPath: posterPath)
                requesting = false
            }
        } label: { Label(label, systemImage: "arrow.down.circle") }
            .buttonStyle(GoldButtonStyle())
            .disabled(requesting || imdbID == nil)
    }
}
