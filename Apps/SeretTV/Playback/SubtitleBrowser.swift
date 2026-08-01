import SwiftUI
import DebridUI
import DebridCore

/// Full subtitle search over the paused film. Hebrew and English are pinned; every other language
/// is behind the picker. Results are ranked by how well each subtitle matches the file playing —
/// an exact file-hash match is a sync guarantee, not a guess, so it is badged and sorted first.
struct SubtitleBrowser: View {
    @Bindable var model: PlayerModel
    let onClose: () -> Void

    @State private var languages: [SubtitleLanguage] = SubtitleLanguages.fallback
    @State private var showAllLanguages = false
    @FocusState private var focused: String?

    private let pinned = ["he", "en"]

    private var pinnedLanguages: [SubtitleLanguage] {
        pinned.compactMap { code in languages.first { $0.code == code } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            languagePills
            results
            Spacer(minLength: 0)
        }
        .padding(60)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.Palette.canvas.opacity(0.96).ignoresSafeArea())
        .task {
            if let fetched = try? await SubtitleLanguages.fetch(apiKey: Secrets.openSubtitlesAPIKey),
               !fetched.isEmpty {
                languages = SubtitleLanguages.order(fetched, pinned: pinned)
            }
            if model.subtitleSearchState == .idle {
                await model.searchSubtitles(language: pinned[0])
            }
        }
        .onExitCommand { onClose() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Subtitles for \(model.label)")
                .font(.seret(.title2, .semibold))
                .foregroundStyle(Theme.Palette.textPrimary)
            Text(model.currentSource.releaseNameForMatching)
                .font(.caption.monospaced())
                .foregroundStyle(Theme.Palette.textSecondary)
                .lineLimit(1)
        }
    }

    private var languagePills: some View {
        HStack(spacing: 12) {
            ForEach(pinnedLanguages) { language in
                Button(language.name) {
                    Task { await model.searchSubtitles(language: language.code) }
                }
                .buttonStyle(SeretActionButtonStyle())
                .focused($focused, equals: "lang-\(language.code)")
            }
            Button(showAllLanguages ? "Hide languages" : "More languages") {
                showAllLanguages.toggle()
            }
            .buttonStyle(SeretActionButtonStyle())
            Spacer()
            if model.subtitleSearchState == .loaded {
                Text("Best match first")
                    .font(.seretCaption).foregroundStyle(Theme.Palette.textSecondary)
            }
        }
        .focusSection()
        .overlay(alignment: .topLeading) {
            if showAllLanguages { languageMenu }
        }
    }

    private var languageMenu: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(languages) { language in
                    Button(language.name) {
                        showAllLanguages = false
                        Task { await model.searchSubtitles(language: language.code) }
                    }
                    .buttonStyle(SeretActionButtonStyle())
                }
            }
            .padding(12)
        }
        .frame(width: 420, height: 520)
        .background(Theme.Palette.surface2, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.Palette.hairline))
        .offset(y: 70)
        .focusSection()
    }

    @ViewBuilder private var results: some View {
        switch model.subtitleSearchState {
        case .idle, .searching:
            HStack(spacing: 12) {
                ProgressView().tint(Theme.Palette.gold)
                Text("Searching…").foregroundStyle(Theme.Palette.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 60)
        case .failed:
            Text("Couldn't search subtitles. Check the OpenSubtitles account in Settings.")
                .foregroundStyle(Theme.Palette.textSecondary)
                .padding(.top, 40)
        case .loaded where model.subtitleSearchResults.isEmpty:
            Text("No subtitles found in this language.")
                .foregroundStyle(Theme.Palette.textSecondary)
                .padding(.top, 40)
        case .loaded:
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(model.subtitleSearchResults, id: \.result.fileID) { ranked in
                        Button {
                            Task { await model.useSubtitle(ranked); onClose() }
                        } label: {
                            row(ranked)
                        }
                        .buttonStyle(.card)
                        .focused($focused, equals: "sub-\(ranked.result.fileID)")
                    }
                }
                .padding(.vertical, 8)
            }
            .focusSection()
        }
    }

    private func row(_ ranked: SubtitleMatch.Ranked) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 10) {
                badge(ranked.quality)
                if ranked.reasons.contains(.fpsMismatch) {
                    Text("may need a timing nudge")
                        .font(.seretCaption).foregroundStyle(Theme.Palette.textSecondary)
                }
                Spacer()
                if let downloads = ranked.result.downloadCount {
                    Label(downloads.formatted(.number), systemImage: "arrow.down.circle")
                        .font(.seretCaption).foregroundStyle(Theme.Palette.textSecondary)
                }
            }
            Text(ranked.result.release ?? ranked.result.fileName ?? "Subtitle")
                .font(.body.monospaced()).lineLimit(1)
                .foregroundStyle(Theme.Palette.textPrimary)
            Text(subtitleDetail(ranked.result))
                .font(.seretCaption).foregroundStyle(Theme.Palette.textSecondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func subtitleDetail(_ result: SubtitleResult) -> String {
        var parts: [String] = [result.language.uppercased()]
        if let fps = result.fps { parts.append(String(format: "%.3f fps", fps)) }
        if result.hearingImpaired == true { parts.append("hearing impaired") }
        if let uploader = result.uploader { parts.append("by \(uploader)") }
        return parts.joined(separator: " · ")
    }

    private func badge(_ quality: SubtitleMatch.Quality) -> some View {
        let (text, color): (String, Color) = switch quality {
        case .perfect:   ("✓ Perfect match", Color.green)
        case .good:      ("Same release group", Theme.Palette.gold)
        case .uncertain: ("Different source", Theme.Palette.textSecondary)
        }
        return Text(text)
            .font(.seret(.caption2, .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10).padding(.vertical, 3)
            .background(color.opacity(0.18), in: Capsule())
    }
}
