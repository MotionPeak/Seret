import SwiftUI

/// Small capsule for metadata (2160p, HDR, TrueHD…).
struct QualityChip: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 11, weight: .bold))
            .foregroundStyle(Theme.Palette.textPrimary)
            .padding(.vertical, 4).padding(.horizontal, 8)
            .background(Theme.Palette.glass,
                        in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
    }
}

/// The title hero's chips (2160p · HDR · Atmos): white text in a white outline, no fill, as g3
/// draws them over the art's fade — a filled chip there read as a second row of buttons.
struct OutlineChip: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 13, weight: .bold))
            .foregroundStyle(Theme.Palette.textPrimary)
            .lineLimit(1)
            .fixedSize()
            .padding(.vertical, 5).padding(.horizontal, 10)
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                .strokeBorder(Theme.Palette.textPrimary.opacity(0.55), lineWidth: 1))
    }
}
