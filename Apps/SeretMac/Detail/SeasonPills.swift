import DebridCore
import DebridUI
import SwiftUI

/// One capsule per `store.allSeasons` (Specials last, per `SeasonOrder`). The selected pill is the
/// gold gradient; tapping another asks the store to switch — it owns loading that season's
/// episodes and watch state.
struct SeasonPills: View {
    let store: DetailStore

    var body: some View {
        HStack(spacing: 10) {
            ForEach(store.allSeasons, id: \.self) { season in
                SeasonPill(title: SeasonOrder.label(season), isSelected: store.selectedSeason == season) {
                    Task { await store.selectSeason(season) }
                }
            }
        }
    }
}

private struct SeasonPill: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(isSelected ? Theme.Palette.onGold : Theme.Palette.textSecondary)
                .padding(.vertical, 8)
                .padding(.horizontal, 16)
                .background { fill }
        }
        .buttonStyle(.plain)
        .offset(y: hovering && !isSelected && !reduceMotion ? -2 : 0)
        .goldGlow(isSelected ? 10 : 0, opacity: isSelected ? 0.35 : 0)
        .animation(Theme.Motion.quick, value: hovering)
        .onHover { hovering = $0 }
    }

    @ViewBuilder private var fill: some View {
        if isSelected {
            Capsule().fill(Theme.Palette.goldGradient)
        } else {
            Capsule().fill(Color.white.opacity(0.06))
        }
    }
}
