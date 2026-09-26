import DebridCore
import DebridUI
import SwiftUI

/// Add by Magnet's content: paste a magnet link or bare info-hash, validate it, download.
///
/// A standalone view over an explicit `MagnetAddModel` (Decision 7 — a sheet's dependencies are
/// passed in, never read from `@Environment`), reused by the `-uiPreview` harness inline as well
/// as `TitlePage` presenting it as a real `.sheet`. The X button and Esc use `\.dismiss` directly
/// (a no-op outside a real presentation, which the harness relies on) rather than a fourth
/// parameter — only a successful submit needs to tell the caller anything.
struct MagnetSheet: View {
    let model: MagnetAddModel
    let title: String
    /// Called once `submit()` lands in `.submitted` — the caller dismisses and shows the toast.
    let onDone: () -> Void
    /// Harness-only: seeds the text field (and validates it) so a screenshot doesn't have to type.
    var initialText: String = ""

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var text: String

    init(model: MagnetAddModel, title: String, onDone: @escaping () -> Void, initialText: String = "") {
        self.model = model; self.title = title; self.onDone = onDone; self.initialText = initialText
        _text = State(initialValue: initialText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Text("Paste a magnet link or an info\u{2011}hash. Real\u{2011}Debrid downloads it and it joins this title.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.Palette.textSecondary)
            editor
            HStack(spacing: 12) {
                Button("Paste \u{2318}V") {
                    if let pasted = NSPasteboard.general.string(forType: .string) {
                        text = pasted
                        model.update(text: text)
                    }
                }
                .buttonStyle(GlassButtonStyle())
                .keyboardShortcut("v", modifiers: .command)
                validationLine
                Spacer(minLength: 0)
                Button {
                    Task {
                        await model.submit()
                        if case .submitted = model.state { onDone() }
                    }
                } label: {
                    Label("Download", systemImage: "arrow.down.circle.fill")
                }
                .buttonStyle(GoldButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canSubmit)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(width: 560, height: 320, alignment: .topLeading)
        .background(Theme.Palette.canvas, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onExitCommand { dismiss() }
        .onAppear {
            guard !initialText.isEmpty else { return }
            model.update(text: initialText)
        }
    }

    private var header: some View {
        HStack {
            Text("Add by Magnet \u{00B7} \(title)")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Theme.Palette.textPrimary)
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .frame(width: 28, height: 28)
                    .glassEffect(.regular.interactive(), in: Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private var editor: some View {
        TextEditor(text: $text)
            .font(.system(size: 12, design: .monospaced))
            .scrollContentBackground(.hidden)
            .padding(8)
            .frame(height: 90)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text("magnet:?xt=urn:btih:\u{2026}")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.Palette.textSecondary.opacity(0.6))
                        .padding(.horizontal, 12).padding(.vertical, 14)
                        .allowsHitTesting(false)
                }
            }
            .onChange(of: text) { _, newValue in model.update(text: newValue) }
    }

    @ViewBuilder private var validationLine: some View {
        switch model.state {
        case .idle, .submitted:
            EmptyView()
        case .invalid:
            Text("That isn\u{2019}t a magnet link or info\u{2011}hash.")
                .font(.system(size: 12)).foregroundStyle(.orange)
        case .ready(let name):
            Text("\u{2713} \(name)")
                .font(.system(size: 12)).foregroundStyle(.green)
                .lineLimit(1)
        case .submitting:
            Label {
                Text("Sending\u{2026}").font(.system(size: 12))
            } icon: {
                Image(systemName: "ellipsis").symbolEffect(.pulse, isActive: !reduceMotion)
            }
            .foregroundStyle(Theme.Palette.textSecondary)
        case .failed(let reason):
            Text(reason).font(.system(size: 12)).foregroundStyle(.red)
        }
    }
}
