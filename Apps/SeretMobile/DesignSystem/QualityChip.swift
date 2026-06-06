import SwiftUI

/// Small capsule for metadata (2160p, HDR, TrueHD…).
struct QualityChip: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 11, weight: .bold))
            .foregroundStyle(Theme.Palette.textPrimary)
            .padding(.vertical, 4).padding(.horizontal, 8)
            .background(Theme.Palette.chipFill,
                        in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
    }
}
