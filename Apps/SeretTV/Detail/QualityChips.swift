import DebridCore
import DebridUI
import SwiftUI

/// Renders the quality/source/codec chips for a parsed release.
struct QualityChips: View {
    let parsed: ParsedRelease

    var body: some View {
        HStack(spacing: 8) {
            if chips.isEmpty {
                // No parseable quality metadata — show the release name so the row is never blank.
                Text(parsed.title)
                    .font(.seret(.caption1, .medium))
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .lineLimit(1)
            } else {
                ForEach(chips, id: \.self) { chip($0) }
            }
        }
    }

    private var chips: [String] {
        [parsed.resolution, parsed.source, parsed.videoCodec, parsed.audioCodec].compactMap { $0 }
    }

    /// Outlined, Plex's certification-chip look: legible over the art without a filled block.
    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.seret(.caption1, .semibold))
            .foregroundStyle(Theme.Palette.textPrimary)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Theme.Palette.glassFaint, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.Palette.textPrimary.opacity(0.35), lineWidth: 1.5))
            // A chip is a word, never a column: squeezed in a full Versions row it broke into
            // "2160 / p" and "REM / UX". The row's other text gives way instead.
            .fixedSize()
    }
}
