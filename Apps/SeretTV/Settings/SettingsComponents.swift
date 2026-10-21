import DebridUI
import SwiftUI

// The building blocks every settings page is made of: a two-pane layout, glass rows, section
// headers, and the pane on the left that explains whichever row holds focus.
//
// The rows say as little as possible — a name and the current value. Everything a row used to
// explain in a caption under it now lives in the left pane and appears only while that row is
// focused, so the list stays a calm column of names and values.

// MARK: - Layout

/// A settings page: the title and the explanation pane on the left, the rows on the right.
///
/// The root Settings page and every page pushed from it use this one layout at one set of
/// coordinates, so pushing a page swaps the title, pane and rows in place rather than moving the
/// whole screen.
struct SettingsPageLayout<Pane: View, Rows: View>: View {
    let title: String
    /// The root page sits beside the side menu (`sideMenuContentInset()` already clears it); a
    /// pushed page is full-bleed and clears the menu's footprint itself, so both line up.
    var clearsSideMenu = false
    @ViewBuilder var pane: Pane
    @ViewBuilder var rows: Rows

    /// Sized so a focused row's right edge (menu 150 + margin 60 + pane + gap + rows) stays
    /// inside the 90pt title-safe edge — at 1000 the rows ran to x≈1870, off a TV's overscan.
    static var paneWidth: CGFloat { 540 }
    static var rowsWidth: CGFloat { 920 }

    var body: some View {
        ZStack(alignment: .topLeading) {
            CanvasBackground()
            HStack(alignment: .top, spacing: 80) {
                VStack(alignment: .leading, spacing: 64) {
                    Text(title)
                        .screenTitle()
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .lineLimit(1)
                    pane
                }
                .frame(width: Self.paneWidth, alignment: .leading)
                .padding(.top, 40)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        rows
                    }
                    // Room for the focused row's lift at both ends of the list.
                    .padding(.top, 44)
                    .padding(.bottom, 90)
                    .padding(.horizontal, 16)
                    // ⚠️ Full width FIRST, then the section: a section only catches a move when its
                    // frame meets the direction of travel (CLAUDE.md, `.focusSection()`).
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .focusSection()
                }
                .frame(width: Self.rowsWidth + 32)
            }
            .padding(.leading, (clearsSideMenu ? SideMenu.footprint : 0) + Theme.Layout.contentMargin)
            .padding(.trailing, Theme.Layout.contentMargin)
            // Measured from the screen's edge, as the shell measures the root page — otherwise a
            // pushed page also took tvOS's leading safe inset and sat ~40pt right of the root.
            .ignoresSafeArea(.container, edges: .leading)
        }
    }
}

/// A section's name above its rows.
struct SettingsSectionHeader: View {
    let title: String
    var first = false

    var body: some View {
        Text(title)
            .eyebrow()
            .foregroundStyle(Theme.Palette.textTertiary)
            .padding(.leading, SettingsRowStyle.inset)
            .padding(.top, first ? 0 : 46)
            .padding(.bottom, 14)
    }
}

/// A quiet line under a section — state that is worth seeing but is not a control, so it never
/// takes focus and appearing cannot move the row in focus.
struct SettingsFootnote: View {
    let text: String
    var isError = false

    var body: some View {
        Text(text)
            .font(.seret(Theme.Typography.captionSize, .medium))
            .foregroundStyle(isError ? Theme.Palette.destructive : Theme.Palette.textSecondary)
            .padding(.leading, SettingsRowStyle.inset)
            .padding(.top, 12)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Rows

/// A row's name, its current value, and what pressing it does (opens a page, picks a choice).
struct SettingsRowLabel: View {
    enum Accessory { case none, chevron, check(Bool) }

    let title: String
    var value: String? = nil
    /// A colour dot before the value — the subtitle colour.
    var swatch: Color? = nil
    var accessory: Accessory = .none

    var body: some View {
        HStack(spacing: 16) {
            Text(title)
                .font(.seret(Theme.Typography.cardSize, .medium))
                .lineLimit(1)
            Spacer(minLength: 28)
            if let swatch {
                Circle()
                    .fill(swatch)
                    .frame(width: 22, height: 22)
                    // The outline is what keeps White visible on the focused (white) row.
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.4), lineWidth: 1.5))
            }
            if let value, !value.isEmpty {
                // `.secondary` follows the row's tint: grey on glass, dark grey on the white pill.
                Text(value)
                    .font(.seret(26, .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            switch accessory {
            case .none:
                EmptyView()
            case .chevron:
                Image(systemName: "chevron.right")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.secondary)
            case .check(let on):
                Image(systemName: "checkmark")
                    .font(.system(size: 24, weight: .bold))
                    .opacity(on ? 1 : 0)
            }
        }
        .contentShape(Rectangle())
    }
}

/// A row that does something in place: flips a switch, runs a check, signs out.
struct SettingsRow: View {
    let title: String
    var value: String? = nil
    var swatch: Color? = nil
    var destructive = false
    /// What the page's pane says while this row is focused. Nil on a page whose pane is fixed.
    var help: SettingsHelpContent? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SettingsRowLabel(title: title, value: value, swatch: swatch)
        }
        .buttonStyle(SettingsRowStyle(destructive: destructive))
        .reportsSettingsHelp(help)
    }
}

/// An On/Off row. Pressing it flips the value; the row stays put, so focus never moves.
struct SettingsToggleRow: View {
    let title: String
    @Binding var isOn: Bool
    let help: SettingsHelpContent

    var body: some View {
        SettingsRow(title: title, value: isOn ? "On" : "Off", help: help) { isOn.toggle() }
    }
}

/// A row that opens a page of its own.
struct SettingsLinkRow: View {
    let title: String
    var value: String? = nil
    var swatch: Color? = nil
    let page: SettingsPage
    let help: SettingsHelpContent

    var body: some View {
        NavigationLink(value: page) {
            SettingsRowLabel(title: title, value: value, swatch: swatch, accessory: .chevron)
        }
        .buttonStyle(SettingsRowStyle())
        .reportsSettingsHelp(help)
    }
}

/// The row's look — the player settings sheet's row, on glass. Glass at rest; focus alone turns it
/// solid white with dark content. A destructive row keeps its red: red text at rest, a red fill
/// when focused.
struct SettingsRowStyle: ButtonStyle {
    var destructive = false

    /// The rows' text inset, which section headers and footnotes share so every left edge lines up.
    static let inset: CGFloat = 34
    static let height: CGFloat = 84

    func makeBody(configuration: Configuration) -> some View {
        Render(configuration: configuration, destructive: destructive)
    }

    private struct Render: View {
        let configuration: ButtonStyleConfiguration
        let destructive: Bool
        @Environment(\.isFocused) private var focused

        var body: some View {
            configuration.label
                .foregroundStyle(textColor)
                .padding(.horizontal, SettingsRowStyle.inset)
                .frame(maxWidth: .infinity, minHeight: SettingsRowStyle.height, alignment: .leading)
                .background(fill, in: Capsule())
                .scaleEffect(focused ? 1.02 : 1)
                .opacity(configuration.isPressed ? 0.7 : 1)
                .padding(.vertical, 5)
                .animation(Theme.Anim.focus, value: focused)
        }

        private var textColor: Color {
            if destructive { return focused ? .white : Theme.Palette.destructive }
            return focused ? Theme.Palette.onFocus : Theme.Palette.textPrimary
        }

        private var fill: Color {
            if focused { return destructive ? Theme.Palette.destructive : Theme.Palette.focus }
            return Theme.Palette.glassFaint
        }
    }
}

// MARK: - The explanation pane

/// What the left pane says about a row while it holds focus.
struct SettingsHelpContent: Hashable {
    /// The section's symbol, drawn large in the pane.
    var icon: String
    var title: String
    var text: String
    var isError = false
    /// Draw a sample subtitle in the current style above the text.
    var showsSubtitleSample = false
}

/// The row in focus, as far as the pane is concerned. Rows write it; only the pane reads it, so a
/// focus move redraws the pane and nothing else.
@MainActor @Observable
final class SettingsHelp {
    var current: SettingsHelpContent?
}

extension View {
    /// Shows `help` in the page's pane while this row holds focus — and again whenever it changes
    /// under a focused row (an import counting up, a connection test finishing).
    func reportsSettingsHelp(_ help: SettingsHelpContent?) -> some View {
        modifier(ReportsSettingsHelp(help: help))
    }
}

private struct ReportsSettingsHelp: ViewModifier {
    let help: SettingsHelpContent?
    // Optional: a row drawn outside a settings page (a harness) simply has no pane to feed.
    @Environment(SettingsHelp.self) private var model: SettingsHelp?
    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        content
            .focused($focused)
            .onChange(of: focused) { _, isFocused in
                if isFocused, let help { model?.current = help }
            }
            .onChange(of: help) { _, new in
                if focused, let new { model?.current = new }
            }
    }
}

/// The left pane: the focused row's section symbol, its name and what it does. Holds the last
/// row's text when focus leaves for the side menu, so the pane never blanks mid-glance.
struct SettingsHelpPane: View {
    let content: SettingsHelpContent?
    var subtitleStyle: SubtitlePreferences = .default

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let content {
                VStack(alignment: .leading, spacing: 26) {
                    if content.showsSubtitleSample {
                        SubtitleSample(style: subtitleStyle)
                    } else {
                        SettingsSymbol(icon: content.icon)
                    }
                    Text(content.title)
                        .sectionTitle()
                        .foregroundStyle(Theme.Palette.textPrimary)
                    Text(content.text)
                        .calloutText()
                        .lineSpacing(6)
                        .foregroundStyle(content.isError ? Theme.Palette.destructive
                                                         : Theme.Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .id(content)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .animation(Theme.Anim.previewIn, value: content)
    }
}

/// A section's symbol in a glass disc.
struct SettingsSymbol: View {
    let icon: String

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 52, weight: .regular))
            .foregroundStyle(Theme.Palette.textPrimary)
            .frame(width: 128, height: 128)
            .background(Theme.Palette.glass, in: Circle())
    }
}

/// A frame of "film" with a subtitle line on it, drawn in a subtitle style — so a size, font or
/// colour can be judged before a film is playing.
///
/// An approximation: libvlc draws the real thing with freetype, its own outline and its own
/// scaling. Faces the system does not have fall back to the system font here.
struct SubtitleSample: View {
    let style: SubtitlePreferences

    static let size = CGSize(width: 540, height: 304)

    var body: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(colors: [Color(hex: 0x2A3346), Color(hex: 0x10141D)],
                           startPoint: .top, endPoint: .bottom)
            VStack(spacing: 4) {
                Text("Subtitles will look like this")
                Text("כתוביות ייראו כך")
            }
            .font(font)
            .multilineTextAlignment(.center)
            .foregroundStyle(Color(hex: UInt(style.color.rgb)))
            .shadow(color: .black.opacity(0.9), radius: 1.5, x: 0, y: 1)
            .shadow(color: .black.opacity(0.6), radius: 4)
            .padding(.horizontal, 20)
            .padding(.bottom, 22)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .strokeBorder(Theme.Palette.hairline, lineWidth: 1))
    }

    private var font: Font {
        let pointSize = 26 * style.size.scale
        if let name = style.font.freetypeName, UIFont(name: name, size: pointSize) != nil {
            return .custom(name, fixedSize: pointSize)
        }
        return .system(size: pointSize, weight: .medium)
    }
}
