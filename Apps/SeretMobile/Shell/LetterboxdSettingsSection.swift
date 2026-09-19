import DebridCore
import DebridUI
import SwiftUI

/// Letterboxd import controls. iPhone/iPad only — this is where the username gets typed, because
/// typing one on a TV remote is a punishment. The Apple TV reads the same setting.
struct LetterboxdSettingsSection: View {
    @Environment(AppSession.self) private var session
    @Bindable var model: LetterboxdImportModel
    let profileID: String?
    /// Built lazily so the section does not probe the network just by being drawn.
    @State private var connection: ServerConnectionTest?
    /// Nil until an address is set; the rows below then have nothing to report.
    let push: LetterboxdPushCoordinator?

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

            // Typed here and read on the Apple TV, like the username: removing a film from the
            // watchlist has to be written by a real browser, and only the server has one.
            TextField("Seret server, e.g. 192.168.1.179:8080", text: Binding(
                get: { model.settings.serverURL },
                set: { var s = model.settings; s.serverURL = $0; model.update(s) }))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)

            // The field is free text with no feedback, which is how `:8000` got typed for a
            // server on `:8080` — a refused connection the app could only describe as "couldn't
            // reach your Seret server". One tap now answers it.
            Button("Test connection") {
                let test = session.makeServerConnectionTest(address: model.settings.serverURL)
                connection = test
                Task { await test.run() }
            }
            .disabled(model.settings.serverURL.trimmingCharacters(in: .whitespaces).isEmpty)

            if let connection { connectionStatus(connection) }

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

            if model.pendingPushes > 0 {
                Text("\(model.pendingPushes) watch\(model.pendingPushes == 1 ? "" : "es") waiting to send")
                    .font(.footnote)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            if let error = model.lastPushError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }

            if let last = model.settings.lastImportAt {
                Text("Last imported \(last.formatted(date: .abbreviated, time: .shortened))")
                    .font(.footnote)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
        }
        .listRowBackground(Theme.Palette.surface1)
        .task { await model.refreshPushStatus(from: push) }
    }

    /// The outcome, in the owner's terms. Deliberately says which fault it was: a wrong port, a
    /// server answering badly and an unreachable host need three different fixes.
    @ViewBuilder
    private func connectionStatus(_ test: ServerConnectionTest) -> some View {
        switch test.result {
        case .untested:
            EmptyView()
        case .needsAddress:
            Text("Enter an address first").font(.footnote)
                .foregroundStyle(Theme.Palette.textSecondary)
        case .testing:
            HStack(spacing: 8) {
                ProgressView()
                Text("Testing…").font(.footnote).foregroundStyle(Theme.Palette.textSecondary)
            }
        case .reachable(let address):
            Label("Reached \(address)", systemImage: "checkmark.circle.fill")
                .font(.footnote)
                .foregroundStyle(.green)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(.red)
        }
    }
}
