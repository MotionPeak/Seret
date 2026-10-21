import DebridUI
import SwiftUI

/// The pages a settings row can open. Pushed on the shell's stack — never a cover — so Menu pops
/// back to the row that opened it, the way every other page in the app goes back.
enum SettingsPage: Hashable {
    case subtitleSize, subtitleFont, subtitleColor, openSubtitles
}

/// One choice out of a short list — the subtitle size, font or colour.
///
/// Opens with focus on the current choice; pressing a choice keeps it and goes back. For subtitle
/// settings the pane draws a sample in the FOCUSED choice, so gliding down the list previews each
/// one before anything is changed.
struct SettingsChoicePage<Option: Hashable>: View {
    let title: String
    let note: String
    let options: [Option]
    let label: (Option) -> String
    @Binding var selection: Option
    var swatch: ((Option) -> Color)? = nil
    /// The subtitle style with `Option` applied, for the pane's sample. Nil draws no sample.
    var sample: ((Option) -> SubtitlePreferences)? = nil
    var icon = "captions.bubble.fill"

    @FocusState private var focused: Option?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SettingsPageLayout(title: title, clearsSideMenu: true) {
            VStack(alignment: .leading, spacing: 26) {
                if let sample {
                    SubtitleSample(style: sample(focused ?? selection))
                        .animation(Theme.Anim.previewIn, value: focused)
                } else {
                    SettingsSymbol(icon: icon)
                }
                Text(note)
                    .calloutText()
                    .lineSpacing(6)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } rows: {
            ForEach(options, id: \.self) { option in
                Button {
                    selection = option
                    dismiss()
                } label: {
                    SettingsRowLabel(title: label(option), swatch: swatch?(option),
                                     accessory: .check(option == selection))
                }
                .buttonStyle(SettingsRowStyle())
                .focused($focused, equals: option)
            }
        }
        // Seeded on appear, as the player's settings sheet does: the rows are on screen, and the
        // list opens on what is set now rather than on its first entry.
        .onAppear { focused = selection }
    }
}
