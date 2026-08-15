import DebridCore
import DebridUI
import SwiftUI
import UIKit   // UIPasteboard — SwiftUI does not import it transitively

/// Paste a magnet link for one title or episode. Presented as a sheet from the detail screens.
///
/// Owns only the session wiring; the visible content is `MagnetAddForm`, which takes a model
/// directly so a DEBUG harness can drive it into each state without a session or a network.
struct MagnetAddSheet: View {
    let target: MagnetAddModel.Target
    /// OPTIONAL on purpose. A sheet is its own presentation context, and a non-optional
    /// `@Environment` read of an Observable that did not cross that boundary TRAPS at runtime —
    /// the crash signature behind the August stability sweep. Both call sites pass
    /// `.environment(session)`, but reading it optionally means a future one that forgets
    /// degrades to the sign-in message instead of killing the app.
    @Environment(AppSession.self) private var session: AppSession?
    @Environment(\.dismiss) private var dismiss

    @State private var model: MagnetAddModel?

    var body: some View {
        NavigationStack {
            Group {
                if let model {
                    MagnetAddForm(model: model, onSubmitted: { dismiss() })
                } else {
                    // No download store means no signed-in session; say so rather than
                    // presenting a form whose Download button could never work.
                    ContentUnavailableView("Sign in to add a magnet",
                                           systemImage: "link.badge.plus")
                }
            }
            .navigationTitle("Add by Magnet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .onAppear {
            if model == nil, let downloads = session?.downloadStore {
                model = MagnetAddModel(target: target, downloads: downloads)
            }
        }
    }
}

/// The paste form itself. Session-free by design — see `MagnetAddSheet`.
struct MagnetAddForm: View {
    let model: MagnetAddModel
    var onSubmitted: () -> Void = {}

    @State private var text = ""

    var body: some View {
        Form {
            Section {
                TextField("magnet:?xt=urn:btih:…", text: $text, axis: .vertical)
                    .lineLimit(3...6)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(Theme.Typo.body())
                    .onChange(of: text) { _, new in model.update(text: new) }

                // Reading UIPasteboard shows the system "Allow Paste" prompt every time.
                // That is the correct trade here: the alternative, `PasteButton`, cannot be
                // styled inside a Form row and reads worse than one extra tap.
                Button {
                    if let pasted = UIPasteboard.general.string { text = pasted }
                } label: {
                    Label("Paste from Clipboard", systemImage: "doc.on.clipboard")
                }
            } footer: {
                statusFooter
            }

            Section {
                Button {
                    Task {
                        await model.submit()
                        if case .submitted = model.state { onSubmitted() }
                    }
                } label: {
                    HStack {
                        if case .submitting = model.state {
                            ProgressView().tint(Theme.Palette.gold)
                        }
                        Text("Download")
                    }
                    .frame(maxWidth: .infinity)
                }
                .disabled(!model.canSubmit)
            }
        }
    }

    @ViewBuilder private var statusFooter: some View {
        switch model.state {
        case .invalid:
            Label("That isn't a magnet link or infohash.", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        case .ready(let name):
            Label(name, systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .lineLimit(2)
        case .failed(let reason):
            Label(reason, systemImage: "xmark.circle").foregroundStyle(.orange)
        default:
            Text("Paste a magnet link. Real‑Debrid downloads it and it appears under this title.")
        }
    }
}
