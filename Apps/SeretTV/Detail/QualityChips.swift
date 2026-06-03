import DebridCore
import SwiftUI

/// Renders the quality/source/codec chips for a parsed release.
struct QualityChips: View {
    let parsed: ParsedRelease

    var body: some View {
        HStack(spacing: 8) {
            ForEach(chips, id: \.self) { chip($0) }
        }
    }

    private var chips: [String] {
        [parsed.resolution, parsed.source, parsed.videoCodec, parsed.audioCodec].compactMap { $0 }
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(.white.opacity(0.12), in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.2)))
    }
}
