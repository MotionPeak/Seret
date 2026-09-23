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
                Button(SeasonOrder.label(season)) {
                    Task { await store.selectSeason(season) }
                }
                .buttonStyle(PillButtonStyle(selected: store.selectedSeason == season))
            }
        }
    }
}
