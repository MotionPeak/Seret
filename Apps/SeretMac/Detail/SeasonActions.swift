import DebridCore
import DebridUI
import SwiftUI

/// Sits trailing in the pills row (`HStack { SeasonPills; Spacer; SeasonActions }`): Mark Season
/// Watched/Unwatched, Download Whole Season (checking → adding → progress, or "No full‑season
/// version"), and Add by Magnet for whichever season is selected. Keeps its own height across
/// phases so switching seasons never jumps the episode grid below it.
struct SeasonActions: View {
    let store: DetailStore
    let acquirer: TitleAcquirer?
    let onMagnet: () -> Void

    @Environment(ShellModel.self) private var shell: ShellModel?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var season: Int { store.selectedSeason }
    private var phase: TitleAcquirer.SeasonPhase { acquirer?.seasonPhase(season) ?? .idle }

    /// TMDB knows about episodes this season that you don't own yet — the gate for offering
    /// Download Whole Season at all.
    private var hasMissingEpisodes: Bool {
        let rows = store.episodes(forSeason: season)
        return rows.contains { !$0.isDownloaded }
    }

    var body: some View {
        HStack(spacing: 10) {
            if store.hasOwnedEpisodes(inSeason: season) {
                Button {
                    Task { await markSeason() }
                } label: {
                    Text(store.isSeasonWatched(season) ? "Mark Season Unwatched" : "Mark Season Watched")
                }
                .buttonStyle(GlassButtonStyle())
            }
            downloadControl
            Button {
                onMagnet()
            } label: {
                Label("Add by Magnet", systemImage: "link")
            }
            .buttonStyle(GlassButtonStyle())
        }
        .fixedSize(horizontal: true, vertical: false)
        .frame(minHeight: 34)
    }

    @ViewBuilder private var downloadControl: some View {
        switch phase {
        case .idle:
            if hasMissingEpisodes {
                Button {
                    Task { await acquirer?.downloadSeason(season) }
                } label: {
                    Label("Download Whole Season", systemImage: "arrow.down.circle")
                }
                .buttonStyle(GoldButtonStyle())
            }
        case .checking, .adding:
            Label {
                Text(TitlePageText.seasonLine(phase, season: season) ?? "")
            } icon: {
                Image(systemName: "ellipsis")
                    .symbolEffect(.pulse, isActive: !reduceMotion)
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.white.opacity(0.85))
        case .downloading(let status):
            HStack(spacing: 10) {
                Text(TitlePageText.seasonLine(phase, season: season) ?? "")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.85))
                GoldProgressBar(fraction: status.fraction).frame(width: 160)
            }
        case .added:
            Label {
                Text("Whole season added")
            } icon: {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.Palette.gold)
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.white.opacity(0.85))
        case .noFullSeason:
            Text("No full\u{2011}season version")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.Palette.textSecondary)
        case .failed(let message):
            HStack(spacing: 10) {
                Label {
                    Text(message.isEmpty ? "Couldn\u{2019}t download the season." : message)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.85))
                } icon: {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                }
                Button("Try Again") { Task { await acquirer?.downloadSeason(season) } }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.Palette.gold)
            }
        }
    }

    private func markSeason() async {
        let newValue = !store.isSeasonWatched(season)
        await store.setSeasonWatched(newValue, season: season)
        shell?.showToast(newValue ? "Marked season \(season) watched" : "Marked season \(season) unwatched")
    }
}
