import DebridCore
import DebridUI
import SwiftUI

/// One capsule per `store.allSeasons` (Specials last, per `SeasonOrder`). The selected pill is the
/// gold gradient; tapping another asks the store to switch — it owns loading that season's
/// episodes and watch state. A season with anything owned carries a small gold dot.
struct SeasonPills: View {
    let store: DetailStore

    var body: some View {
        HStack(spacing: 10) {
            ForEach(store.allSeasons, id: \.self) { season in
                SeasonPill(season: season, selected: store.selectedSeason == season,
                          owned: store.hasOwnedEpisodes(inSeason: season)) {
                    Task { await store.selectSeason(season) }
                }
            }
        }
    }
}

private struct SeasonPill: View {
    let season: Int
    let selected: Bool
    let owned: Bool
    let onSelect: () -> Void

    var body: some View {
        let button = Button(action: onSelect) {
            HStack(spacing: 6) {
                Text(SeasonOrder.label(season))
                if owned {
                    Circle().fill(Theme.Palette.gold).frame(width: 5, height: 5)
                }
            }
        }
        .buttonStyle(PillButtonStyle(selected: selected))

        if owned {
            button.help("In your library")
        } else {
            button
        }
    }
}
