import SwiftUI

/// Grouped settings on the glass language, in place of the system `Form`'s grey inset look: a
/// quiet uppercase heading, a glass card of rows split by hairlines, and a footnote under it — on
/// the navy canvas. Settings, the Letterboxd section and the OpenSubtitles sign-in use it.
///
/// Every text field is a `GlassField`, whose name sits ABOVE the value and stays there once
/// something is typed (a `Form` row shows no title for a field, so a filled-in field said nothing
/// about what it was — audit #9).
struct GlassSection<Content: View>: View {
    var title: String?
    var footer: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            if let title {
                Text(title.uppercased())
                    .font(.system(size: 12, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .padding(.horizontal, Theme.Space.lg)
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(spacing: 0) {
                Group(subviews: content) { rows in
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        row
                        if index < rows.count - 1 {
                            Rectangle().fill(Theme.Palette.hairline).frame(height: 0.5)
                                .padding(.leading, Theme.Space.lg)
                        }
                    }
                }
            }
            .seretGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous), interactive: false)
            if let footer {
                Text(footer)
                    .font(.footnote)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Theme.Space.lg)
            }
        }
    }
}

/// A row's padding and height — every row in a `GlassSection` sits on it.
struct GlassRow<Content: View>: View {
    var tint: Color = Theme.Palette.textPrimary
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: Theme.Space.md) { content }
            .font(.system(size: 17))
            .foregroundStyle(tint)
            .padding(.horizontal, Theme.Space.lg)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
            .contentShape(Rectangle())
    }
}

/// A labelled text field: the name above, the value under it.
struct GlassField: View {
    let label: String
    @Binding var text: String
    var prompt: String = ""
    var secure = false
    var keyboard: UIKeyboardType = .default
    /// Usernames, addresses and passwords: no capitals, no corrections.
    var plain = true
    var contentType: UITextContentType?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.Palette.textSecondary)
            Group {
                if secure {
                    SecureField(label, text: $text, prompt: promptText)
                } else {
                    TextField(label, text: $text, prompt: promptText)
                }
            }
            .font(.system(size: 17))
            .foregroundStyle(Theme.Palette.textPrimary)
            .keyboardType(keyboard)
            .textContentType(contentType)
            .textInputAutocapitalization(plain ? .never : .sentences)
            .autocorrectionDisabled(plain)
        }
        .padding(.horizontal, Theme.Space.lg)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var promptText: Text {
        Text(prompt).foregroundStyle(Theme.Palette.textTertiary)
    }
}

/// A switch row. On is green, not white: a white track under the white knob reads as off.
struct GlassToggleRow: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        GlassRow {
            Toggle(title, isOn: $isOn)
                .tint(Theme.Palette.toggleOn)
        }
    }
}

/// A choice row: the name on the left, the current value as a menu on the right.
struct GlassPickerRow<Value: Hashable, Options: View>: View {
    let title: String
    @Binding var selection: Value
    @ViewBuilder var options: Options

    var body: some View {
        GlassRow {
            Text(title)
            Spacer(minLength: Theme.Space.sm)
            Picker(title, selection: $selection) { options }
                .pickerStyle(.menu)
                .labelsHidden()
                .tint(Theme.Palette.textSecondary)
        }
    }
}

/// A row that goes somewhere (a `NavigationLink`'s label): icon, title, chevron.
struct GlassLinkRow: View {
    let title: String
    let systemImage: String

    var body: some View {
        GlassRow {
            Image(systemName: systemImage)
                .frame(width: 24)
                .foregroundStyle(Theme.Palette.textSecondary)
            Text(title)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.Palette.textTertiary)
        }
    }
}

/// A plain status row: icon and text, optionally in the destructive colour.
struct GlassLabelRow: View {
    let title: String
    let systemImage: String
    var tint: Color = Theme.Palette.textPrimary
    var iconTint: Color = Theme.Palette.textSecondary

    var body: some View {
        GlassRow {
            Image(systemName: systemImage)
                .frame(width: 24)
                .foregroundStyle(iconTint)
            Text(title).foregroundStyle(tint)
            Spacer(minLength: 0)
        }
    }
}

/// A row that is a button: the whole row is the target.
struct GlassButtonRow: View {
    let title: String
    var systemImage: String?
    var destructive = false
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            GlassRow(tint: destructive ? Theme.Palette.destructive : Theme.Palette.textPrimary) {
                if let systemImage {
                    Image(systemName: systemImage).frame(width: 24)
                }
                Text(title)
                Spacer(minLength: 0)
            }
            .opacity(isEnabled ? 1 : 0.4)
        }
        .buttonStyle(GlassRowPressStyle())
    }
}

/// A row's press: a faint white wash, as a list row highlights.
struct GlassRowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Color.white.opacity(configuration.isPressed ? 0.08 : 0))
    }
}

/// The page under grouped glass sections: the canvas, a scroll, the sections spaced out and kept
/// to a readable width on iPad.
struct GlassFormPage<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xxl) { content }
                .frame(maxWidth: 640)
                .padding(.horizontal, Theme.Space.lg)
                .padding(.top, Theme.Space.md)
                .padding(.bottom, Theme.Space.xxxl)
                .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(CanvasBackground())
    }
}
