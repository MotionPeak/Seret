import DebridUI
import SwiftUI

/// The Hebrew-subtitles mark: on a version row, and larger in a title's hero.
///
/// A glass chip with white text, never the solid white that means "focused" in this app: whether a version can be watched with Hebrew
/// subtitles is the first thing this household asks of it. The two kinds look different on
/// purpose. A track inside the file is always in sync, so it is lit, carries a seal and says so;
/// its row draws it on a line of its own at the top. Matched and Available keep the flat pill.
struct HebrewBadge: View {
    let indicator: HebrewIndicator
    var prominent = false

    init(_ indicator: HebrewIndicator, prominent: Bool = false) {
        self.indicator = indicator
        self.prominent = prominent
    }

    var body: some View {
        if indicator == .inFile { inFile } else { pill }
    }

    private var pill: some View {
        Label(indicator.title, systemImage: indicator.systemImage)
            .font(.seret(prominent ? .callout : .caption1, .bold))
            // Available: Hebrew exists for the film, but not made for this version — quieter text.
            .foregroundStyle(indicator == .available ? Theme.Palette.textSecondary : Theme.Palette.textPrimary)
            .padding(.horizontal, prominent ? 16 : 12)
            .padding(.vertical, prominent ? 8 : 5)
            .background(Theme.Palette.glass, in: Capsule())
    }

    private var inFile: some View {
        HStack(spacing: prominent ? 10 : 8) {
            Image(systemName: indicator.systemImage)
            Text(indicator.title)
            if let detail = indicator.detail {
                Text("·").opacity(0.45)
                Text(detail).font(.seret(prominent ? .callout : .caption1, .medium))
            }
        }
        .font(.seret(prominent ? .callout : .caption1, .bold))
        .foregroundStyle(Theme.Palette.textPrimary)
        .padding(.horizontal, prominent ? 18 : 14)
        .padding(.vertical, prominent ? 8 : 6)
        .background(Theme.Palette.glass, in: Capsule())
        // The emphasis that says "in sync": an outline, not a fill.
        .overlay(Capsule().strokeBorder(Theme.Palette.strokeStrong, lineWidth: 1.5))
    }
}
