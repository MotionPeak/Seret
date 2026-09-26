import DebridCore
import DebridUI
import SwiftUI

/// The sidebar's downloads card, directly above Settings: a gold progress ring + count, the item
/// nearest done, and a click that opens the full list in a popover. Absent — not an empty card —
/// when nothing is downloading.
struct SidebarDownloadsCard: View {
    let summary: DownloadsSummary
    let collapsed: Bool

    @Environment(DownloadStore.self) private var injectedStore: DownloadStore?
    @Environment(AppSession.self) private var session: AppSession?
    @Environment(LibraryStore.self) private var injectedLibrary: LibraryStore?
    @Environment(ShellModel.self) private var shell: ShellModel?
    @State private var showingPopover = false

    private var store: DownloadStore? { injectedStore ?? session?.downloadStore }
    private var library: LibraryStore? { injectedLibrary ?? session?.libraryStore }

    var body: some View {
        Group {
            if summary.count > 0 {
                Button { showingPopover = true } label: { content }
                    .buttonStyle(.plain)
                    .help(summary.helpText)
                    .popover(isPresented: $showingPopover, arrowEdge: .trailing) {
                        DownloadsPopover(tiles: store?.activeTiles ?? [], library: library) { item in
                            showingPopover = false
                            shell?.open(.title(item))
                        }
                    }
                    .transition(.opacity)
            }
        }
        .animation(Theme.Motion.quick, value: summary.count > 0)
    }

    @ViewBuilder private var content: some View {
        if collapsed {
            ring.frame(maxWidth: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    ring
                    Text("Downloading")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.Palette.gold)
                    Spacer(minLength: 0)
                }
                if let leadLine = summary.leadLine {
                    Text(leadLine)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                if let lead = summary.lead {
                    GoldProgressBar(fraction: lead.status.fraction).frame(height: 3)
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
        }
    }

    private var ring: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.14), lineWidth: 3.2)
            Circle().trim(from: 0, to: max(0, min(1, summary.fraction)))
                .stroke(Theme.Palette.gold, style: StrokeStyle(lineWidth: 3.2, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .goldGlow(6, opacity: 0.5)
            Text("\(summary.count)")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(Theme.Palette.gold)
        }
        .frame(width: 30, height: 30)
    }
}
