import DebridCore
import DebridUI
import SwiftUI

/// Letterboxd import, Apple TV side.
///
/// The username stays read-only here on purpose: typing one on a remote is a punishment, and the
/// setting is the same iCloud-synced key the iPhone writes. Set it there, import from either.
///
/// Everything else the import needs, though, must be settable HERE. "Import my ratings" used to
/// live only on the iPhone while this card gated its button on it — and a `.disabled` button is
/// removed from tvOS's focus system entirely, so the whole card became unreachable: pressing DOWN
/// jumped from the card above straight to the card below it. A switch is exactly the kind of thing
/// a remote is good at, so it is offered on both faces.
struct LetterboxdCard: View {
    @Environment(AppSession.self) private var session
    @Bindable var model: LetterboxdImportModel
    let profileID: String?
    /// Built lazily so the card does not probe the network just by being drawn.
    @State private var connection: ServerConnectionTest?
    /// Nil until a server address is set. Read-only here: the address is typed on the iPhone and
    /// arrives through iCloud, exactly as the username does.
    let push: LetterboxdPushCoordinator?

    private var hasUsername: Bool { !model.settings.username.isEmpty }
    private var hasProfile: Bool { profileID?.isEmpty == false }
    private var canImport: Bool { model.settings.isEnabled && hasUsername && hasProfile }

    /// Writes through to the same store the iPhone uses, so the switch means the same thing on
    /// both devices.
    private var isEnabled: Binding<Bool> {
        Binding(get: { model.settings.isEnabled },
                set: { var s = model.settings; s.isEnabled = $0; model.update(s) })
    }

    /// Why the import cannot run, in the owner's terms. Nil when it can.
    ///
    /// This is shown instead of a disabled button, never alongside one: a control the remote
    /// cannot reach explains nothing, and that is the whole defect this card had.
    private var blockedReason: String? {
        if !hasUsername { return "Set your Letterboxd username on your iPhone, in Seret → Settings." }
        if !model.settings.isEnabled { return "Turn on “Import my ratings” to bring your Letterboxd ratings in." }
        if !hasProfile { return "Still getting ready — try again in a moment." }
        return nil
    }

    var body: some View {
        SettingsCard(title: "Letterboxd", icon: "film.stack") {
            VStack(alignment: .leading, spacing: 16) {
                if hasUsername {
                    Text(model.settings.username)
                        .foregroundStyle(Theme.Palette.textPrimary)
                }

                // Always present, so the card always has something the remote can land on —
                // whatever else is or isn't set up.
                Toggle("Import my ratings", isOn: isEnabled)

                phaseContent
                pushStatus

                serverRow
            }
        }
        .task { await model.refreshPushStatus(from: push) }
    }

    /// Finished films waiting to reach Letterboxd, and why the last one did not.
    ///
    /// The Apple TV is where films actually get finished, so this is the device most likely to be
    /// holding a queue — and the one with no other way to find out.
    @ViewBuilder private var pushStatus: some View {
        if model.pendingPushes > 0 {
            Text("\(model.pendingPushes) watch\(model.pendingPushes == 1 ? "" : "es") waiting to send")
                .settingsCaption()
        }
        if let error = model.lastPushError {
            Text(error).settingsCaption()
        }
    }

    @ViewBuilder private var phaseContent: some View {
        switch model.phase {
        case .idle:
            importAction("Import Ratings")

        case .running(let done, let total):
            Text(total > 0 ? "Matching \(done) of \(total)…" : "Reading your profile…")
                .settingsCaption()

        case .finished(let summary):
            Text(summary.written == 0
                 ? "Nothing new to fill in"
                 : "Filled in \(summary.written) rating\(summary.written == 1 ? "" : "s")")
                .foregroundStyle(Theme.Palette.textPrimary)
            if summary.conflicts > 0 {
                Text("\(summary.conflicts) rated differently here — kept yours")
                    .settingsCaption()
            }
            if summary.unresolved > 0 {
                Text("\(summary.unresolved) not found on Letterboxd")
                    .settingsCaption()
            }
            importAction("Import Again")

        case .failed(let message):
            // The palette's error colour rather than a raw `.red`, which the app uses nowhere else.
            Text(message).foregroundStyle(Theme.Palette.destructive)
            importAction("Try Again")
        }
    }

    /// The button when the import can actually run, and the reason it can't when it can't.
    @ViewBuilder private func importAction(_ title: String) -> some View {
        if canImport {
            Button(title) { Task { await model.importNow(profileID: profileID) } }
                .buttonStyle(SeretActionButtonStyle())
        } else if let blockedReason {
            Text(blockedReason).settingsCaption()
        }
    }

    /// "Can this Apple TV reach the server?", asked from the device that has to.
    ///
    /// The address is typed on the iPhone and only read here, so this is the one place the answer
    /// is meaningful: the TV's own cleartext rules and local-network permission decide it, and
    /// reachability from a phone or a laptop says nothing about them. It is also the only warning
    /// anyone gets before a removal silently fails to reach Letterboxd.
    @ViewBuilder private var serverRow: some View {
        let address = model.settings.serverURL
        VStack(alignment: .leading, spacing: 10) {
            Text(address.isEmpty
                 ? "No Seret server set — add one on your iPhone to push changes to Letterboxd."
                 : "Seret server: \(address)")
                .settingsCaption()

            if !address.isEmpty {
                Button("Test Connection") {
                    let test = session.makeServerConnectionTest(address: address)
                    connection = test
                    Task { await test.run() }
                }
                .buttonStyle(SeretPillStyle(selected: false))

                if let connection { connectionStatus(connection) }
            }
        }
    }

    @ViewBuilder
    private func connectionStatus(_ test: ServerConnectionTest) -> some View {
        switch test.result {
        case .untested, .needsAddress:
            EmptyView()
        case .testing:
            HStack(spacing: 10) {
                ProgressView().tint(Theme.Palette.gold)
                Text("Testing…").settingsCaption()
            }
        case .reachable(let address):
            SettingsStatus(text: "Reached \(address)", good: true)
        case .failed(let message):
            Text(message).calloutText().foregroundStyle(Theme.Palette.destructive)
        }
    }
}
