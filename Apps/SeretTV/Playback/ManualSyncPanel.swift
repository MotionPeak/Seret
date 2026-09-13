import SwiftUI
import DebridUI
import DebridCore

/// Sync a subtitle to a line you can hear.
///
/// Sits at the TOP of the picture, like the settings panel, because subtitles render near the
/// bottom and the entire point is watching the lines land while you dial. Nothing pauses.
///
/// One focusable pad with four fixed directions — no list to enter and no focus to lose, which is
/// the trap this app has paid for repeatedly.
struct ManualSyncPanel: View {
    @Bindable var model: PlayerModel
    let onClose: () -> Void

    /// Seeds focus onto the pad when the panel opens, so the remote drives it immediately.
    /// `@FocusState` + `.onAppear` is the reliable seed for a panel like this one — the same
    /// pattern `SettingsPanel` uses, and the opposite of the Detail screen's `.defaultFocus`.
    @FocusState private var padFocused: Bool

    var body: some View {
        Group {
            if let readout = model.manualSyncReadout {
                card(readout)
            }
        }
        .padding(.horizontal, Theme.Layout.contentMargin)
        .padding(.top, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func card(_ readout: PlayerModel.ManualSyncReadout) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            header
            lines(readout)
            pad(readout)
            legend
        }
        .padding(.horizontal, 48)
        .padding(.vertical, 36)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Theme.Palette.canvas.opacity(0.92))
                .overlay(RoundedRectangle(cornerRadius: 24)
                    .stroke(Theme.Palette.gold.opacity(0.18), lineWidth: 1))
        )
    }

    private var header: some View {
        Text("SYNC TO A LINE")
            .font(.seret(.caption2, .semibold))
            .tracking(1.1)
            .foregroundStyle(Theme.Palette.textSecondary)
    }

    /// The selected line with its neighbours. The list does not scroll — the slice is recomputed
    /// around the selection, so moving through it changes the text in place.
    private func lines(_ readout: PlayerModel.ManualSyncReadout) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(readout.lines) { cue in
                let isSelected = cue.id == readout.selected.id
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    Text(isSelected ? "▸" : " ")
                        .font(.seretCallout)
                        .foregroundStyle(Theme.Palette.gold)
                    Text(cue.text.isEmpty ? "—" : cue.text)
                        .font(isSelected ? .seretTitle3 : .seretCallout)
                        .foregroundStyle(isSelected ? Theme.Palette.textPrimary
                                                    : Theme.Palette.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 24)
                    Text(Timecode.format(cue.start))
                        .font(.seretCallout)
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .monospacedDigit()
                }
                .opacity(isSelected ? 1 : 0.55)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The one focusable thing on screen. Select captures the moment; the directions move the line
    /// and nudge the offset.
    ///
    /// `.onMoveCommand` traps focus here DELIBERATELY — the panel is modal and Menu is the way out.
    /// (The warning in CLAUDE.md about `.onMoveCommand` on a focusable row is about the Detail
    /// screen, where trapping focus is the bug. Do not "fix" this one.)
    private func pad(_ readout: PlayerModel.ManualSyncReadout) -> some View {
        Button(action: { model.markSyncMoment() }) {
            Group {
                if let offset = readout.offset {
                    HStack(spacing: 18) {
                        Text(String(format: "%+.1fs", offset))
                            .font(.seretTitle)
                            .monospacedDigit()
                        // Dimmed by OPACITY, not by a palette colour: this sits on the gold fill,
                        // where textSecondary — a grey tuned for the dark canvas — is barely
                        // legible. Inheriting the button's own dark foreground keeps the contrast.
                        Text(offset >= 0 ? "subtitles now show later"
                                         : "subtitles now show earlier")
                            .font(.seretCallout)
                            .opacity(0.65)
                    }
                } else {
                    Text("Press SELECT the moment this line is spoken")
                        .font(.seretTitle3)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(SeretActionButtonStyle())
        .focused($padFocused)
        .onAppear { padFocused = true }
        .onMoveCommand { direction in
            switch direction {
            case .up:    model.moveSyncLine(by: -1)
            case .down:  model.moveSyncLine(by: 1)
            case .left:  model.nudgeSyncOffset(by: -0.1)
            case .right: model.nudgeSyncOffset(by: 0.1)
            @unknown default: break
            }
        }
    }

    /// The arrows carry `\u{FE0E}` (text presentation): without it the system renders ◀ and ▶ as
    /// blue EMOJI while ▲ and ▼ stay as text, so the legend came out half-coloured.
    private var legend: some View {
        Text("▲\u{FE0E}▼\u{FE0E} change line     ◀\u{FE0E}▶\u{FE0E} nudge 0.1s     MENU done")
            .font(.seret(.caption2, .semibold))
            .tracking(1.1)
            .foregroundStyle(Theme.Palette.textSecondary)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}
