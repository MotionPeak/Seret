import DebridCore
import DebridUI
import SwiftUI

/// An owned film's copies: ✓ on the one Play uses, chips, release group, size, ▶ to play. Shown
/// only for a movie with ≥ 1 version — `TitlePage` gates its presence entirely.
struct VersionsSection: View {
    let store: DetailStore
    let onFindOtherVersions: () -> Void
    let onRemoveVersion: (MediaSource) -> Void

    @Environment(ShellModel.self) private var shell: ShellModel?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("VERSIONS")
                    .font(Theme.Typo.label())
                    .tracking(1.5)
                    .foregroundStyle(Theme.Palette.gold)
                Spacer()
                Button("Find Other Versions\u{2026}", action: onFindOtherVersions)
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.Palette.gold)
            }
            ForEach(store.versions, id: \.self) { source in
                VersionRow(source: source, isActive: store.isActive(source),
                          hebrew: HebrewIndicator(store.hebrew(for: source)),
                          menu: VersionMenu.make(isPreferred: store.isActive(source),
                                                 hasPreference: store.preferredSourceKey != nil),
                          onPlay: { play(source) }, onMenu: { perform($0, source) })
            }
        }
        .frame(maxWidth: 1020, alignment: .leading)
    }

    private func play(_ source: MediaSource) {
        shell?.present(store.playRequest(source: source, episode: nil, label: store.item.title))
    }

    private func perform(_ item: VersionMenuItem, _ source: MediaSource) {
        switch item {
        case .playThis: play(source)
        case .makeDefault: Task { await store.chooseVersion(source) }
        case .useBestAutomatically: Task { await store.clearPreferredVersion() }
        case .remove: onRemoveVersion(source)
        }
    }
}

/// One owned version's row: 44 pt tall, 10 pt corners, a faint white fill that brightens on hover.
/// Every hover action (the row itself, ▶) is duplicated in the right-click menu. A version with
/// Hebrew inside the file grows a line on top for its mark, as in the Versions sheet.
private struct VersionRow: View {
    let source: MediaSource
    let isActive: Bool
    let hebrew: HebrewIndicator?
    let menu: [[VersionMenuItem]]
    let onPlay: () -> Void
    let onMenu: (VersionMenuItem) -> Void

    @State private var hovering = false

    private var parts: (chips: [String], group: String?, size: String?) { VersionText.ownedRow(source) }

    var body: some View {
        Button(action: onPlay) {
            VStack(alignment: .leading, spacing: 6) {
                if hebrew == .inFile { HebrewBadge(.inFile) }
                line
            }
            .padding(.horizontal, 14)
            .padding(.vertical, hebrew == .inFile ? 10 : 0)
            .frame(minHeight: 44)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(hovering ? 0.06 : 0.04),
                       in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .contextMenu { menuContent }
    }

    private var line: some View {
        HStack(spacing: 12) {
            Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isActive ? Theme.Palette.gold : Theme.Palette.textSecondary)
            ForEach(parts.chips, id: \.self) { QualityChip(text: $0) }
            if hebrew == .matched { HebrewBadge(.matched) }
            if let group = parts.group {
                Text(group)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 8)
            if let size = parts.size {
                Text(size)
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            Image(systemName: "play.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.Palette.textPrimary)
                .frame(width: 28, height: 28)
                .glassEffect(.regular.interactive(), in: Circle())
        }
    }

    @ViewBuilder private var menuContent: some View {
        ForEach(Array(menu.enumerated()), id: \.offset) { index, group in
            if index > 0 { Divider() }
            ForEach(group, id: \.self) { item in
                Button {
                    onMenu(item)
                } label: {
                    Label(item.title, systemImage: item.symbol)
                }
            }
        }
    }
}
