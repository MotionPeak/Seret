import DebridUI
import SwiftUI

/// The Hebrew-subtitles mark: on a version row, and larger in a title's hero.
///
/// Gold so it reads before the grey chips around it: whether a version can be watched with Hebrew
/// subtitles is the first thing this household asks of it. The two kinds look different on
/// purpose. A track inside the file is always in sync, so it is lit, carries a seal and says so;
/// its row draws it on a line of its own at the top. Matched and Available keep the flat pill.
/// The wording and symbols come from `HebrewIndicator`, so Apple TV, iPhone and the Mac agree.
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
            .labelStyle(.titleAndIcon)
            .font(.system(size: prominent ? 12 : 11, weight: .bold))
            .foregroundStyle(Theme.Palette.onGold)
            .padding(.horizontal, prominent ? 10 : 8)
            .padding(.vertical, 4)
            // Available: Hebrew exists for the film, but not made for this version.
            .background(Theme.Palette.gold.opacity(indicator == .available ? 0.6 : 1), in: Capsule())
            .fixedSize()
    }

    private var inFile: some View {
        HStack(spacing: 5) {
            Image(systemName: indicator.systemImage)
            Text(indicator.title)
            if let detail = indicator.detail {
                Text("·").opacity(0.45)
                Text(detail).fontWeight(.medium)
            }
        }
        .font(.system(size: prominent ? 12 : 11, weight: .bold))
        .foregroundStyle(Theme.Palette.onGold)
        .padding(.horizontal, prominent ? 11 : 9)
        .padding(.vertical, 4)
        .background(Theme.Palette.markGradient, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.Palette.goldBright, lineWidth: 1))
        .shadow(color: Theme.Palette.goldGlow, radius: prominent ? 8 : 6)
        .fixedSize()
    }
}
