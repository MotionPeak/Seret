import DebridCore
import DebridUI
import SwiftUI
import UIKit   // UIPasteboard — SwiftUI does not import it transitively

/// Paste a magnet link for one title or episode. Presented as a sheet from the detail screens.
struct MagnetAddSheet: View {
    let target: MagnetAddModel.Target
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var model: MagnetAddModel?
    @State private var text = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("magnet:?xt=urn:btih:…", text: $text, axis: .vertical)
                        .lineLimit(3...6)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(Theme.Typo.body())
                        .onChange(of: text) { _, new in model?.update(text: new) }

                    // Reading UIPasteboard shows the system "Allow Paste" prompt every time.
                    // That is the correct trade here: the alternative, `PasteButton`, cannot be
                    // styled inside a Form row and reads worse than one extra tap.
                    Button {
                        if let pasted = UIPasteboard.general.string {
                            text = pasted
                        }
                    } label: {
                        Label("Paste from Clipboard", systemImage: "doc.on.clipboard")
                    }
                } footer: {
                    statusFooter
                }

                Section {
                    Button {
                        Task {
                            await model?.submit()
                            if case .submitted = model?.state { dismiss() }
                        }
                    } label: {
                        HStack {
                            if case .submitting = model?.state {
                                ProgressView().tint(Theme.Palette.gold)
                            }
                            Text("Download")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(!(model?.canSubmit ?? false))
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
            if model == nil, let downloads = session.downloadStore {
                model = MagnetAddModel(target: target, downloads: downloads)
            }
        }
    }

    @ViewBuilder private var statusFooter: some View {
        switch model?.state {
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
