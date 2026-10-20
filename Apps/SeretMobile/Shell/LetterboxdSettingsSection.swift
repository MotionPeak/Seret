import DebridCore
import DebridUI
import SwiftUI

/// Letterboxd controls, as three glass sections — the account (username, rating import, marks),
/// the shared watchlist (a partner's), and the Seret server. iPhone/iPad only — this is where the
/// username gets typed, because typing one on a TV remote is a punishment. The Apple TV reads the
/// same setting.
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

    /// One field of the settings, written straight back through the model.
    private func setting(_ keyPath: WritableKeyPath<LetterboxdSettings, String>) -> Binding<String> {
        Binding(get: { model.settings[keyPath: keyPath] },
                set: { var s = model.settings; s[keyPath: keyPath] = $0; model.update(s) })
    }

    private func setting(_ keyPath: WritableKeyPath<LetterboxdSettings, Bool>) -> Binding<Bool> {
        Binding(get: { model.settings[keyPath: keyPath] },
                set: { var s = model.settings; s[keyPath: keyPath] = $0; model.update(s) })
    }

    private var hasPartner: Bool {
        !model.settings.partnerUsername.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxl) {
            // Every field carries its name above it, so a filled-in field still says what it is.
            GlassSection(title: "Letterboxd",
                         footer: "Your watchlist and ratings come from your public Letterboxd profile.") {
                GlassToggleRow(title: "Import my ratings", isOn: setting(\.isEnabled))
                GlassField(label: "Username", text: setting(\.username), prompt: "Letterboxd username")
                // A mark is often a skim. Films finished in the player log regardless.
                GlassToggleRow(title: "Log films I mark watched", isOn: setting(\.logsMarkedFilms))
                importRows
            }

            // A second public watchlist, shown merged with the owner's. Read only — nothing is ever
            // written to that account, which the footnote says so nobody has to wonder.
            GlassSection(title: "Shared watchlist",
                         footer: hasPartner
                            ? "Their watchlist is shown with yours. Nothing is written to their account."
                            : "Show someone else's public watchlist merged with yours.") {
                GlassField(label: "Also show watchlist of", text: setting(\.partnerUsername),
                           prompt: "Letterboxd username")
                if hasPartner {
                    GlassField(label: "Their name", text: setting(\.partnerName), prompt: "e.g. Noga",
                               plain: false)
                }
            }

            // Typed here and read on the Apple TV, like the username: removing a film from the
            // watchlist has to be written by a real browser, and only the server has one.
            GlassSection(title: "Seret server",
                         footer: "Removing a film from your watchlist is sent to Letterboxd through your Seret server.") {
                GlassField(label: "Server address", text: setting(\.serverURL), prompt: "192.168.1.179:8080",
                           keyboard: .URL)
                // The field is free text with no feedback, which is how `:8000` got typed for a
                // server on `:8080` — a refused connection the app could only describe as "couldn't
                // reach your Seret server". One tap now answers it.
                GlassButtonRow(title: "Test connection", systemImage: "network") {
                    let test = session.makeServerConnectionTest(address: model.settings.serverURL)
                    connection = test
                    Task { await test.run() }
                }
                .disabled(model.settings.serverURL.trimmingCharacters(in: .whitespaces).isEmpty)
                if let connection, connection.result != .untested {
                    GlassRow { connectionStatus(connection) }
                }
            }
        }
        .task { await model.refreshPushStatus(from: push) }
    }

    /// Import now / progress / the last result, then what is waiting to be sent.
    @ViewBuilder private var importRows: some View {
        switch model.phase {
        case .idle:
            GlassButtonRow(title: "Import now", systemImage: "arrow.down.circle") {
                Task { await model.importNow(profileID: profileID) }
            }
            .disabled(!canImport)

        case .running(let done, let total):
            GlassRow {
                ProgressView().tint(Theme.Palette.textSecondary)
                Text(total > 0 ? "Matching \(done) of \(total)…" : "Reading your profile…")
                    .foregroundStyle(Theme.Palette.textSecondary)
            }

        case .finished(let summary):
            GlassRow {
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
            }
            GlassButtonRow(title: "Import again", systemImage: "arrow.clockwise") {
                Task { await model.importNow(profileID: profileID) }
            }
            .disabled(!canImport)

        case .failed(let message):
            GlassRow {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.Palette.destructive)
            }
            GlassButtonRow(title: "Try again", systemImage: "arrow.clockwise") {
                Task { await model.importNow(profileID: profileID) }
            }
            .disabled(!canImport)
        }

        if model.pendingPushes > 0 || model.lastPushError != nil || model.settings.lastImportAt != nil {
            GlassRow {
                VStack(alignment: .leading, spacing: 3) {
                    if model.pendingPushes > 0 {
                        Text("\(model.pendingPushes) watch\(model.pendingPushes == 1 ? "" : "es") waiting to send")
                    }
                    if let error = model.lastPushError { Text(error) }
                    if let last = model.settings.lastImportAt {
                        Text("Last imported \(last.formatted(date: .abbreviated, time: .shortened))")
                    }
                }
                .font(.footnote)
                .foregroundStyle(Theme.Palette.textSecondary)
            }
        }
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
                .foregroundStyle(Theme.Palette.toggleOn)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(Theme.Palette.destructive)
        }
    }
}
