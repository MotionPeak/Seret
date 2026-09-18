import DebridCore
import DebridUI
import SwiftUI

/// Letterboxd import controls. iPhone/iPad only — this is where the username gets typed, because
/// typing one on a TV remote is a punishment. The Apple TV reads the same setting.
struct LetterboxdSettingsSection: View {
    @Bindable var model: LetterboxdImportModel
    let profileID: String?

    private var canImport: Bool {
        model.settings.isEnabled && !model.settings.username.isEmpty && profileID?.isEmpty == false
    }

    var body: some View {
        Section("Letterboxd") {
            Toggle("Import my ratings", isOn: Binding(
                get: { model.settings.isEnabled },
                set: { var s = model.settings; s.isEnabled = $0; model.update(s) }))

            TextField("Username", text: Binding(
                get: { model.settings.username },
                set: { var s = model.settings; s.username = $0; model.update(s) }))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            switch model.phase {
            case .idle:
                Button("Import now") { Task { await model.importNow(profileID: profileID) } }
                    .disabled(!canImport)

            case .running(let done, let total):
                HStack(spacing: 10) {
                    ProgressView()
                    Text(total > 0 ? "Matching \(done) of \(total)…" : "Reading your profile…")
                        .foregroundStyle(Theme.Palette.textSecondary)
                }

            case .finished(let summary):
                VStack(alignment: .leading, spacing: 2) {
                    Text(summary.written == 0
                         ? "Nothing new to fill in"
                         : "Filled in \(summary.written) rating\(summary.written == 1 ? "" : "s")")
                    if summary.conflicts > 0 {
                        Text("\(summary.conflicts) rated differently here — kept yours")
                            .font(.footnote)
                            .foregroundStyle(Theme.Palette.textSecondary)
                    }
                    if summary.unresolved > 0 {
                        Text("\(summary.unresolved) not found on Letterboxd")
                            .font(.footnote)
                            .foregroundStyle(Theme.Palette.textSecondary)
                    }
                }
                Button("Import again") { Task { await model.importNow(profileID: profileID) } }
                    .disabled(!canImport)

            case .failed(let message):
                Text(message).foregroundStyle(.red)
                Button("Try again") { Task { await model.importNow(profileID: profileID) } }
                    .disabled(!canImport)
            }

            if let last = model.settings.lastImportAt {
                Text("Last imported \(last.formatted(date: .abbreviated, time: .shortened))")
                    .font(.footnote)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
        }
        .listRowBackground(Theme.Palette.surface1)
    }
}
