import DebridCore
import DebridUI
import SwiftUI

/// Letterboxd import, Apple TV side — a section of rows on the Settings page.
///
/// The username stays read-only here on purpose: typing one on a remote is a punishment, and the
/// setting is the same iCloud-synced key the iPhone writes. Set it there, import from either.
///
/// Everything else the import needs, though, must be settable HERE. "Import my ratings" used to
/// live only on the iPhone while this section gated its button on it — and a `.disabled` button is
/// removed from tvOS's focus system entirely, so the whole card became unreachable. So nothing
/// here is ever disabled: a row that cannot act ignores the press, and the pane says why.
struct LetterboxdSettingsSection: View {
    @Environment(AppSession.self) private var session
    @Bindable var model: LetterboxdImportModel
    let profileID: String?
    /// Nil until a server address is set. Read-only here: the address is typed on the iPhone and
    /// arrives through iCloud, exactly as the username does.
    let push: LetterboxdPushCoordinator?
    /// Built lazily so the section does not probe the network just by being drawn.
    @State private var connection: ServerConnectionTest?

    private static let icon = "film.stack"

    private var hasUsername: Bool { !model.settings.username.isEmpty }
    private var hasProfile: Bool { profileID?.isEmpty == false }
    private var canImport: Bool { model.settings.isEnabled && hasUsername && hasProfile }

    /// Writes through to the same store the iPhone uses, so the switch means the same thing on
    /// both devices.
    private var isEnabled: Binding<Bool> {
        Binding(get: { model.settings.isEnabled },
                set: { var s = model.settings; s.isEnabled = $0; model.update(s) })
    }

    /// Synced like the rest, so it reads the same on every device. Films the player sees to their
    /// credits log regardless — this is about marks only.
    private var logsMarks: Binding<Bool> {
        Binding(get: { model.settings.logsMarkedFilms },
                set: { var s = model.settings; s.logsMarkedFilms = $0; model.update(s) })
    }

    /// Why the import cannot run, in the owner's terms. Nil when it can.
    private var blockedReason: String? {
        if !hasUsername { return "Set your Letterboxd username on your iPhone, in Seret → Settings." }
        if !model.settings.isEnabled { return "Turn on “Import My Ratings” to bring your Letterboxd ratings in." }
        if !hasProfile { return "Still getting ready — try again in a moment." }
        return nil
    }

    var body: some View {
        Group {
            SettingsSectionHeader(title: "Letterboxd")
            // Not a control — the account, set on the iPhone or the Mac. Pressing it does nothing.
            SettingsRow(title: "Account", value: hasUsername ? model.settings.username : "Not set",
                        help: help("Letterboxd", accountText)) {}
            SettingsToggleRow(title: "Import My Ratings", isOn: isEnabled,
                              help: help("Import my ratings",
                                         "Bring the ratings you gave on Letterboxd into Seret."))
            SettingsToggleRow(title: "Log Films I Mark Watched", isOn: logsMarks,
                              help: help("Log films I mark watched",
                                         "Marking a film watched logs it to Letterboxd. Films you finish in the player are always logged."))
            importRow
            serverRow
            pushStatus
        }
        .task { await model.refreshPushStatus(from: push) }
    }

    private func help(_ title: String, _ text: String, isError: Bool = false) -> SettingsHelpContent {
        SettingsHelpContent(icon: Self.icon, title: title, text: text, isError: isError)
    }

    private var accountText: String {
        guard hasUsername else { return "Set your Letterboxd username on your iPhone, in Seret → Settings." }
        var text = "Set on your iPhone or Mac."
        // Set on the iPhone or the Mac, like the username — typed once, read here.
        if model.settings.hasPartner {
            text += " Also showing \(model.settings.partnerDisplayName)'s watchlist."
        }
        return text
    }

    // MARK: - Import

    /// One row through every phase: its words change, the row itself never goes away — so a
    /// press that starts an import cannot throw focus off the screen.
    private var importRow: some View {
        SettingsRow(title: importTitle, value: importValue,
                    help: help("Import ratings", importText, isError: importFailed)) {
            // Running: one import at a time (the model guards too). Blocked: the pane says why.
            if case .running = model.phase { return }
            guard canImport else { return }
            Task { await model.importNow(profileID: profileID) }
        }
    }

    private var importFailed: Bool {
        if case .failed = model.phase { return true }
        return false
    }

    private var importTitle: String {
        switch model.phase {
        case .idle:     "Import Ratings"
        case .running:  "Importing"
        case .finished: "Import Again"
        case .failed:   "Try Again"
        }
    }

    private var importValue: String? {
        switch model.phase {
        case .idle:
            return canImport ? nil : "Not ready"
        case .running(let done, let total):
            return total > 0 ? "\(done) of \(total)" : "Reading…"
        case .finished(let summary):
            return summary.written == 0 ? "Nothing new" : "Filled in \(summary.written)"
        case .failed:
            return "Failed"
        }
    }

    private var importText: String {
        switch model.phase {
        case .idle:
            return blockedReason ?? "Fill in ratings from your Letterboxd profile."
        case .running(let done, let total):
            return total > 0 ? "Matching \(done) of \(total)…" : "Reading your profile…"
        case .finished(let summary):
            var lines = [summary.written == 0
                         ? "Nothing new to fill in."
                         : "Filled in \(summary.written) rating\(summary.written == 1 ? "" : "s")."]
            if summary.conflicts > 0 { lines.append("\(summary.conflicts) rated differently here — kept yours.") }
            if summary.unresolved > 0 { lines.append("\(summary.unresolved) not found on Letterboxd.") }
            if let blockedReason { lines.append(blockedReason) }
            return lines.joined(separator: "\n")
        case .failed(let message):
            return blockedReason.map { "\(message)\n\($0)" } ?? message
        }
    }

    // MARK: - Server

    /// "Can this Apple TV reach the server?", asked from the device that has to.
    ///
    /// The address is typed on the iPhone and only read here, so this is the one place the answer
    /// is meaningful: the TV's own cleartext rules and local-network permission decide it, and
    /// reachability from a phone or a laptop says nothing about them. It is also the only warning
    /// anyone gets before a removal silently fails to reach Letterboxd. Pressing the row runs it.
    private var serverRow: some View {
        let address = model.settings.serverURL
        return SettingsRow(title: "Seret Server", value: serverValue(address),
                           help: help("Seret server", serverText(address), isError: serverFailed)) {
            guard !address.isEmpty else { return }
            let test = session.makeServerConnectionTest(address: address)
            connection = test
            Task { await test.run() }
        }
    }

    private var serverFailed: Bool {
        if case .failed = connection?.result { return true }
        return false
    }

    private func serverValue(_ address: String) -> String {
        guard !address.isEmpty else { return "Not set" }
        switch connection?.result {
        case .testing:   return "Testing…"
        case .reachable: return "Reachable"
        case .failed:    return "Unreachable"
        default:         return address
        }
    }

    private func serverText(_ address: String) -> String {
        guard !address.isEmpty else {
            return "No Seret server set — add one on your iPhone to push changes to Letterboxd."
        }
        switch connection?.result {
        case .testing:
            return "Testing \(address)…"
        case .reachable(let reached):
            return "Reached \(reached)."
        case .failed(let message):
            return message
        default:
            return "Seret server: \(address). Press to test that this Apple TV can reach it."
        }
    }

    // MARK: - Push queue

    /// Finished films waiting to reach Letterboxd, and why the last one did not.
    ///
    /// The Apple TV is where films actually get finished, so this is the device most likely to be
    /// holding a queue — and the one with no other way to find out.
    @ViewBuilder private var pushStatus: some View {
        if model.pendingPushes > 0 {
            SettingsFootnote(text: "\(model.pendingPushes) watch\(model.pendingPushes == 1 ? "" : "es") waiting to send")
        }
        if let error = model.lastPushError {
            SettingsFootnote(text: error, isError: true)
        }
    }
}
