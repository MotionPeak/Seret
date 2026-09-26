import DebridCore
import DebridUI
import SwiftUI

/// What the film download section shows, derived purely from whether a request is in flight and
/// the store's own tracked status — never held as separate view state that could drift from it.
enum DownloadSectionPhase: Equatable {
    case idle
    case starting
    case downloading(fraction: Double, line: String)
    case failed(String)

    static func derive(requesting: Bool, status: DownloadStatus?) -> DownloadSectionPhase {
        guard let status else { return requesting ? .starting : .idle }
        switch status.phase {
        case .queued:
            return .starting
        case .downloading:
            return .downloading(fraction: status.fraction, line: DownloadProgressText.line(for: status))
        case .ready:
            // About to leave the store as the library refreshes and the page upgrades (Decision 3).
            return .idle
        case .failed(let message):
            return .failed(message)
        }
    }
}

/// A film you don't yet own: Request Download → progress → Try Another Version / Cancel Download.
/// Shown only while there is nothing to play — `TitlePage` gates its presence entirely.
struct MovieDownloadSection: View {
    let store: DetailStore
    let acquirer: TitleAcquirer?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(ShellModel.self) private var shell: ShellModel?
    @State private var requesting = false

    private var phase: DownloadSectionPhase {
        DownloadSectionPhase.derive(requesting: requesting, status: acquirer?.status(.movie))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("DOWNLOAD")
                .font(Theme.Typo.label())
                .tracking(1.5)
                .foregroundStyle(Theme.Palette.gold)
            content
        }
        // The list-keeps-its-height rule: every state reserves the tallest one's room, so the
        // section landing on `.downloading` (with its progress bar) never shifts what's below it.
        .frame(minHeight: 96, alignment: .top)
    }

    @ViewBuilder private var content: some View {
        switch phase {
        case .idle:
            VStack(alignment: .leading, spacing: 10) {
                Text("Not in your library yet. Play finds an instant version; if Real\u{2011}Debrid has none, request a download.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .frame(maxWidth: 520, alignment: .leading)
                HStack(spacing: 10) {
                    Button("Request Download") { Task { await request() } }
                        .buttonStyle(GoldButtonStyle())
                    addByMagnetButton
                }
                .fixedSize(horizontal: true, vertical: false)
            }
        case .starting:
            Label {
                Text("Starting download\u{2026}")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.85))
            } icon: {
                Image(systemName: "arrow.down.circle")
                    .symbolEffect(.pulse, isActive: !reduceMotion)
            }
        case .downloading(let fraction, let line):
            VStack(alignment: .leading, spacing: 8) {
                Text(line)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.85))
                GoldProgressBar(fraction: fraction).frame(maxWidth: 520)
                HStack(spacing: 12) {
                    Button("Cancel Download") { Task { await acquirer?.cancelDownload(.movie) } }
                        .buttonStyle(GlassButtonStyle())
                    Text("It\u{2019}ll appear here when it\u{2019}s ready.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
            }
        case .failed(let reason):
            VStack(alignment: .leading, spacing: 10) {
                Label {
                    Text(reason).font(.system(size: 13)).foregroundStyle(Color.white.opacity(0.85))
                } icon: {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                }
                HStack(spacing: 10) {
                    Button("Try Another Version") { Task { await request() } }
                        .buttonStyle(GoldButtonStyle())
                    addByMagnetButton
                }
                .fixedSize(horizontal: true, vertical: false)
            }
        }
    }

    private var addByMagnetButton: some View {
        Button {
            shell?.requestMagnet()
        } label: {
            Label("Add by Magnet\u{2026}", systemImage: "link")
        }
        .buttonStyle(GlassButtonStyle())
    }

    private func request() async {
        guard let acquirer else { return }
        requesting = true
        _ = await acquirer.requestDownload(.movie)
        requesting = false
    }
}
