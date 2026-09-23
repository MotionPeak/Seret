import DebridCore
import DebridUI
import SwiftUI

/// The Watchlist section (spec §6): the Letterboxd watchlist, synced on open when stale and on
/// *Sync*; a status line; a grid (owned ✓, unmatched "No TMDB match" tiles); Remove from Watchlist
/// (confirmed, relayed through the Seret server); and Surprise Me. Without a Letterboxd username
/// it says where to set one.
struct WatchlistRoot: View {
    @Environment(AppSession.self) private var session: AppSession?
    @Environment(WatchlistModel.self) private var injected: WatchlistModel?
    @State private var model: WatchlistModel?

    var body: some View {
        Group {
            if let model = injected ?? model {
                WatchlistScreen(model: model)
            } else {
                unavailable
            }
        }
        .task {
            guard injected == nil else { return }
            if model == nil { model = session?.makeWatchlistModel() }
            await model?.syncIfStale()
        }
    }

    private var unavailable: some View {
        VStack(spacing: 14) {
            Image(systemName: "bookmark")
                .font(.system(size: 40))
                .foregroundStyle(Theme.Palette.gold)
            Text("Your Letterboxd watchlist lives here")
                .font(Theme.Typo.headline())
                .foregroundStyle(Theme.Palette.textPrimary)
            Text("Set your Letterboxd username in Settings.")
                .font(Theme.Typo.body())
                .foregroundStyle(Theme.Palette.textSecondary)
            SettingsLink { Text("Open Settings…") }
                .buttonStyle(GlassButtonStyle())
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct WatchlistScreen: View {
    let model: WatchlistModel
    @Environment(ShellModel.self) private var shell: ShellModel?
    @Environment(\.pageLeadingInset) private var pageLeadingInset
    @State private var spin: WatchlistRandomizer.Spin?
    @State private var pendingRemoval: WatchlistEntry?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Watchlist")
                    .font(Theme.Typo.titleXL())
                    .foregroundStyle(Theme.Palette.textPrimary)
                statusRow
                content
            }
            .padding(.leading, pageLeadingInset)
            .padding(.trailing, 28)
            .padding(.top, 56)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .overlay {
            if let spin {
                SurpriseReel(spin: spin,
                             onWatch: { entry in
                                 self.spin = nil
                                 if let item = MediaItem.watchlistMovie(entry) { shell?.open(.title(item)) }
                             },
                             onSpinAgain: { self.spin = model.spin() },
                             onClose: { self.spin = nil })
                    .transition(.opacity)
            }
        }
        .animation(Theme.Motion.fade, value: spin?.id)
        .confirmationDialog(removalTitle, isPresented: Binding(
            get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } })) {
            Button("Remove", role: .destructive) {
                if let entry = pendingRemoval { Task { await model.remove(entry) } }
                pendingRemoval = nil
            }
        } message: {
            Text("It's removed on Letterboxd too.")
        }
    }

    private var removalTitle: String {
        "Remove \u{201C}\(pendingRemoval.map { WatchlistName.stripYear(from: $0.name) } ?? "")\u{201D} from your watchlist?"
    }

    @ViewBuilder private var statusRow: some View {
        HStack(spacing: 12) {
            switch model.phase {
            case .idle:
                if model.canSpin {
                    Button { spin = model.spin() } label: {
                        Label("Surprise Me", systemImage: "dice.fill")
                    }
                    .buttonStyle(GoldButtonStyle())
                }
                Button("Sync") { Task { await model.syncNow() } }
                    .buttonStyle(GlassButtonStyle())
                if !model.entries.isEmpty {
                    Text("\(model.entries.count) film\(model.entries.count == 1 ? "" : "s")")
                        .font(Theme.Typo.body())
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
                if let message = model.relayMessage {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(Theme.Typo.body())
                        .foregroundStyle(Theme.Palette.destructive)
                        .lineLimit(1)
                }
            case .syncing(let done, let total):
                ProgressView(value: total > 0 ? Double(done) / Double(total) : nil)
                    .frame(width: 120)
                    .tint(Theme.Palette.gold)
                Text(total > 0 ? "Matching \(done) of \(total)…" : "Reading your watchlist…")
                    .font(Theme.Typo.body())
                    .foregroundStyle(Theme.Palette.textSecondary)
            case .failed(let message):
                Button("Try Again") { Task { await model.syncNow() } }
                    .buttonStyle(GlassButtonStyle())
                Text(message)
                    .font(Theme.Typo.body())
                    .foregroundStyle(Theme.Palette.destructive)
                    .lineLimit(2)
            }
        }
    }

    @ViewBuilder private var content: some View {
        if model.entries.isEmpty {
            if case .syncing = model.phase {
                PosterGrid(items: [MediaItem](), isLoading: true) { (_: MediaItem) in EmptyView() }
            } else {
                Text("Nothing on your watchlist yet.")
                    .font(Theme.Typo.body())
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .padding(.top, 20)
            }
        } else {
            PosterGrid(items: model.entries) { entry in
                WatchlistTile(entry: entry, owned: model.isOwned(entry),
                              onOpen: { item in shell?.open(.title(item)) },
                              onRemove: { pendingRemoval = entry })
            }
        }
    }
}

/// One watchlist film: its poster (✓ when it's in your library) or, when TMDB couldn't match it,
/// a named placeholder. Click opens the title page; right-click offers Open and Remove.
private struct WatchlistTile: View {
    let entry: WatchlistEntry
    let owned: Bool
    let onOpen: (MediaItem) -> Void
    let onRemove: () -> Void
    @State private var hovering = false

    private var item: MediaItem? { MediaItem.watchlistMovie(entry) }
    private var title: String { WatchlistName.stripYear(from: entry.name) }

    var body: some View {
        Group {
            if let item {
                Button { onOpen(item) } label: {
                    PosterCard(title: title, caption: entry.year.map(String.init) ?? "",
                               posterURL: TMDBClient.imageURL(path: entry.posterPath, size: "w342"),
                               badge: owned ? .watched : .none, highlighted: hovering)
                }
                .buttonStyle(.plain)
                .onHover { hovering = $0 }
                .animation(Theme.Motion.quick, value: hovering)
            } else {
                unmatched
            }
        }
        .contextMenu {
            if let item { Button("Open") { onOpen(item) } }
            Button("Remove from Watchlist…", role: .destructive, action: onRemove)
        }
        .help(owned ? "\(title) — in your library" : title)
    }

    private var unmatched: some View {
        VStack(alignment: .leading, spacing: 6) {
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Theme.Palette.surface1)
                .frame(width: PosterCard.posterSize.width, height: PosterCard.posterSize.height)
                .overlay {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .padding(10)
                }
            Text("No TMDB match")
                .font(Theme.Typo.caption())
                .foregroundStyle(Theme.Palette.textTertiary)
        }
        .frame(width: PosterCard.posterSize.width, alignment: .leading)
    }
}

/// Surprise Me (spec §6, mockup 3): the winner is chosen first, then a reel of posters runs for
/// 3.1 s and settles in the gold frame; *Watch It* opens it, *Spin Again* re-rolls. Reduce Motion
/// shows the winner straight away.
struct SurpriseReel: View {
    let spin: WatchlistRandomizer.Spin
    let onWatch: (WatchlistEntry) -> Void
    let onSpinAgain: () -> Void
    let onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var offset: CGFloat = 0
    @State private var landed = false

    private let cardWidth: CGFloat = 180
    private let gap: CGFloat = 24
    private var cardHeight: CGFloat { cardWidth * 1.5 }
    private var step: CGFloat { cardWidth + gap }

    var body: some View {
        ZStack {
            // Opaque: the grid behind must not show through the reel's dimmed neighbours.
            Rectangle().fill(.ultraThinMaterial)
                .overlay(Theme.Palette.canvas.opacity(0.94))
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)
            VStack(spacing: 26) {
                Text("SURPRISE ME")
                    .font(Theme.Typo.label()).tracking(2)
                    .foregroundStyle(Theme.Palette.gold)
                GeometryReader { geo in
                    let centreX = geo.size.width / 2 - cardWidth / 2
                    HStack(spacing: gap) {
                        ForEach(Array(spin.reel.enumerated()), id: \.offset) { index, entry in
                            RemoteImage(url: TMDBClient.imageURL(path: entry.posterPath, size: "w342"))
                                .frame(width: cardWidth, height: cardHeight)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .opacity(landed && index != spin.winnerIndex ? 0.35 : 1)
                        }
                    }
                    .offset(x: centreX - offset)
                    .frame(width: geo.size.width, alignment: .leading)
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Theme.Palette.goldGradient, lineWidth: 3)
                            .frame(width: cardWidth + 10, height: cardHeight + 10)
                            .shadow(color: Theme.Palette.gold.opacity(0.6), radius: landed ? 18 : 6)
                    }
                }
                .frame(height: cardHeight + 20)
                .clipped()
                .mask(LinearGradient(colors: [.clear, .black, .black, .clear],
                                     startPoint: .leading, endPoint: .trailing))

                VStack(spacing: 14) {
                    Text(landed ? WatchlistName.stripYear(from: spin.winner.name) : " ")
                        .font(Theme.Typo.title())
                        .foregroundStyle(Theme.Palette.textPrimary)
                    HStack(spacing: 12) {
                        Button { onWatch(spin.winner) } label: { Label("Watch It", systemImage: "play.fill") }
                            .buttonStyle(GoldButtonStyle())
                        Button("Spin Again", action: onSpinAgain)
                            .buttonStyle(GlassButtonStyle())
                        Button("Close", action: onClose)
                            .buttonStyle(GlassButtonStyle())
                            .keyboardShortcut(.cancelAction)
                    }
                    .opacity(landed ? 1 : 0)
                }
            }
            .padding(40)
        }
        .task(id: spin.id) { run() }
    }

    private func run() {
        landed = false
        offset = 0
        let target = CGFloat(spin.winnerIndex) * step
        if reduceMotion {
            offset = target
            landed = true
            return
        }
        withAnimation(.timingCurve(0.12, 0.8, 0.2, 1, duration: 3.1)) { offset = target }
        Task {
            try? await Task.sleep(for: .seconds(3.1))
            withAnimation(Theme.Motion.pop) { landed = true }
        }
    }
}
