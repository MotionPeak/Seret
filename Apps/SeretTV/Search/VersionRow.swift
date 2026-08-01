import DebridCore
import DebridUI
import SwiftUI

/// One release in a versions list: cache badge, year, quality chips, languages, size, and the
/// play/download affordance. Shared by the Add screen's inline "Show all versions" list and the
/// full-screen `VersionsScreen`, so both read identically.
struct VersionRow: View {
    let stream: CachedStream
    /// True while this row's pick is being resolved (instant-add probe / download start).
    let isPicking: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 16) {
                    CacheBadge(isCached: stream.isCached)
                    if let year = stream.parsed.year {
                        Text(String(year)).font(.seret(.caption1, .semibold))
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(.white.opacity(0.12), in: Capsule())
                    }
                    QualityChips(parsed: stream.parsed)
                    LanguageBadges(codes: stream.languages)
                    Spacer()
                    if let size = stream.sizeBytes {
                        Text(Self.sizeGB(size)).font(.seretCallout).foregroundStyle(.secondary)
                    }
                    if isPicking {
                        ProgressView()
                    } else {
                        Image(systemName: stream.isCached ? "play.circle" : "arrow.down.circle")
                    }
                }
                Text(stream.rawTitle).font(.seretCallout).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
        }
        .buttonStyle(SeretRowStyle())
    }

    static func sizeGB(_ bytes: Int) -> String {
        String(format: "%.1f GB", Double(bytes) / 1_000_000_000)
    }
}

/// ⚡ Instant (already on RD) vs ⬇️ Download (will fetch) — from Comet's cache marker.
struct CacheBadge: View {
    let isCached: Bool
    var body: some View {
        Label(isCached ? "Instant" : "Download", systemImage: isCached ? "bolt.fill" : "arrow.down.circle")
            .font(.seret(.caption1, .bold))
            .foregroundStyle(isCached ? Color.green : .yellow)
            .padding(.vertical, 4).padding(.horizontal, 10)
            .background((isCached ? Color.green : .yellow).opacity(0.15), in: Capsule())
    }
}

/// Uppercased ISO-639-1 language chips (e.g. EN · FR).
struct LanguageBadges: View {
    let codes: [String]
    var body: some View {
        HStack(spacing: 8) {
            ForEach(codes.prefix(4), id: \.self) { code in
                Text(code.uppercased())
                    .font(.seret(.caption1, .bold))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(.white.opacity(0.10), in: Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(0.18)))
            }
        }
    }
}
