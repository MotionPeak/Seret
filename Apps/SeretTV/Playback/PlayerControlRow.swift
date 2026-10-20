import SwiftUI

/// One button of the player's control row.
enum PlayerControl: CaseIterable {
    case subtitles, audio, speed, episodes

    var title: String {
        switch self {
        case .subtitles: "Subtitles"
        case .audio:     "Audio"
        case .speed:     "Speed"
        case .episodes:  "Episodes"
        }
    }

    var systemImage: String {
        switch self {
        case .subtitles: "captions.bubble"
        case .audio:     "speaker.wave.2"
        case .speed:     "gauge.with.dots.needle.67percent"
        case .episodes:  "rectangle.stack"
        }
    }

    /// The settings sheet section this button opens; nil for Episodes, which lifts the strip.
    var section: SettingsSection? {
        switch self {
        case .subtitles: .subtitles
        case .audio:     .audio
        case .speed:     .speed
        case .episodes:  nil
        }
    }
}

extension SettingsSection {
    /// The control-row button that opens this section.
    var control: PlayerControl {
        switch self {
        case .subtitles: .subtitles
        case .audio:     .audio
        case .speed:     .speed
        }
    }
}

/// The row Down opens under the scrub bar: glass circles that grow into labelled white pills as
/// focus reaches them (`ExpandingIconButtonStyle`).
///
/// 🚨 FOCUSABLE — so `PlayerView` mounts it only while `showControls` is true and counts that in
/// `inputSurfaceActive`. A focusable sibling of `PlayerInputSurface` at rest is exactly what made
/// touch-scrub and arrow clicks mutually exclusive.
///
/// Up closes it through a thin focus target ABOVE the buttons — the `EpisodeStripExpanded`
/// pattern. The buttons cannot take `.onMoveCommand`: on a focusable row it swallows the arrows
/// and traps focus. With the input surface off while the row is up, nothing else hears Up.
struct PlayerControlRow: View {
    let controls: [PlayerControl]
    let onChoose: (PlayerControl) -> Void
    let onClose: () -> Void
    /// The button focus lands on — the one that opened the side sheet, when the row comes back
    /// after it. The first button otherwise.
    var initialFocus: PlayerControl? = nil

    /// The row's whole height — the close target, the circles and their lift room. `PlayerView`
    /// holds exactly this much under the bar while the side sheet is up, so the bar never moves
    /// between the row and the sheet.
    static let height: CGFloat = 2 + 12 + ExpandingIconButtonStyle.diameter + 12

    private enum Target: Hashable { case control(PlayerControl), close }
    @FocusState private var focused: Target?
    /// Set once a button has held focus. The close target only means "Up from a button": if the
    /// focus engine ever offered it first, the row would close the instant it opened.
    @State private var armed = false

    private var landing: Target? {
        (initialFocus.flatMap { controls.contains($0) ? $0 : nil } ?? controls.first).map { .control($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .frame(maxWidth: .infinity).frame(height: 2)
                .focusable()
                .focused($focused, equals: .close)

            HStack(spacing: 22) {
                ForEach(controls, id: \.self) { control in
                    Button { onChoose(control) } label: {
                        Label(control.title, systemImage: control.systemImage)
                    }
                    .buttonStyle(ExpandingIconButtonStyle())
                    .focused($focused, equals: .control(control))
                }
            }
            // Room for the focused pill's lift, which the row would otherwise clip.
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: Self.height)
        .defaultFocus($focused, landing)
        .onAppear { focused = landing }
        .onChange(of: focused) { _, new in
            switch new {
            case .control?: armed = true
            case .close?:
                if armed { onClose() } else { focused = landing }
            case nil: break
            }
        }
    }
}
