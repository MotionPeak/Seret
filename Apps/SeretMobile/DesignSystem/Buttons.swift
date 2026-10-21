import SwiftUI

/// A label that shows its title and icon, or its icon alone when space is short. The title stays
/// the accessibility label either way, so VoiceOver still reads "Watchlist", not "bookmark".
///
/// The pill and circle button styles live in `Glass.swift`.
struct AdaptiveLabelStyle: LabelStyle {
    let iconOnly: Bool

    @ViewBuilder func makeBody(configuration: Configuration) -> some View {
        if iconOnly {
            Label(configuration).labelStyle(.iconOnly)
        } else {
            Label(configuration).labelStyle(.titleAndIcon)
        }
    }
}
