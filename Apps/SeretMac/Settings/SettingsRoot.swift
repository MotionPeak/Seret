import DebridCore
import DebridUI
import SwiftUI

/// The Settings window (⌘,), spec §6: Accounts (Real-Debrid, OpenSubtitles), Letterboxd (username,
/// ratings import, the Seret server + Test Connection, the send queue), Playback (subtitle size,
/// font and colour with a live preview in the approved style; autoplay trailers) and About.
/// Profiles stay hidden while `ProfilesFeature.isEnabled` is false, as on the other apps.
struct SettingsRoot: View {
    var body: some View {
        TabView {
            Tab("Accounts", systemImage: "person.crop.circle") { AccountsSettings() }
            Tab("Letterboxd", systemImage: "star.circle") { LetterboxdSettings() }
            Tab("Playback", systemImage: "play.rectangle") { PlaybackSettings() }
            Tab("About", systemImage: "info.circle") { AboutSettings() }
        }
        .frame(width: 620, height: 520)
        .preferredColorScheme(.dark)
        .tint(Theme.Palette.gold)
    }
}

// MARK: - Accounts

private struct AccountsSettings: View {
    @Environment(AppSession.self) private var session
    @State private var confirmingSignOut = false
    @State private var openSubtitles = SettingsModel(
        secretStore: KeychainSecretStore(service: "com.solomons.seret.opensubtitles"))

    private var canSignInToOpenSubtitles: Bool {
        !openSubtitles.username.trimmingCharacters(in: .whitespaces).isEmpty && !openSubtitles.password.isEmpty
    }

    var body: some View {
        Form {
            Section("Real-Debrid") {
                LabeledContent("Account") {
                    if session.state == .signedIn {
                        Label("Signed in", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Text("Not signed in").foregroundStyle(.secondary)
                    }
                }
                if session.state == .signedIn {
                    Button("Sign Out…", role: .destructive) { confirmingSignOut = true }
                }
            }

            Section {
                if openSubtitles.isConnected {
                    LabeledContent("Account") {
                        Label("Connected as \(openSubtitles.username)", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                    Button("Disconnect", role: .destructive) { openSubtitles.remove() }
                } else {
                    TextField("Username", text: $openSubtitles.username)
                        .textContentType(.username)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $openSubtitles.password)
                        .textContentType(.password)
                    HStack {
                        Link("Create a free account…",
                             destination: URL(string: "https://www.opensubtitles.com/en/users/sign_up")!)
                            .font(.footnote)
                        Spacer()
                        Button("Sign In") { openSubtitles.save() }
                            .keyboardShortcut(.defaultAction)
                            .disabled(!canSignInToOpenSubtitles)
                    }
                }
            } header: {
                Text("OpenSubtitles")
            } footer: {
                Text("Used to download Hebrew and English subtitles while you watch.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section("iCloud") {
                Label(session.profilesSyncedViaICloud ? "Watch history and ratings sync with your other devices"
                                                      : "On this Mac only — sign in to iCloud to sync",
                      systemImage: session.profilesSyncedViaICloud ? "checkmark.icloud.fill" : "icloud.slash")
                    .foregroundStyle(session.profilesSyncedViaICloud ? Theme.Palette.gold : .secondary)
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Sign out of Real-Debrid on this Mac?", isPresented: $confirmingSignOut) {
            Button("Sign Out", role: .destructive) { Task { await session.signOut() } }
        } message: {
            Text("Your library and watch history stay; you'll sign in again with a code or a token.")
        }
    }
}

// MARK: - Letterboxd

private struct LetterboxdSettings: View {
    @Environment(AppSession.self) private var session
    @State private var model: LetterboxdImportModel?

    var body: some View {
        Group {
            if let model {
                LetterboxdForm(model: model, profileID: session.activeProfileID, push: session.letterboxdPush)
            } else {
                ContentUnavailableView("Sign in to Real-Debrid first", systemImage: "star.circle",
                                       description: Text("Letterboxd matches your ratings against your library."))
            }
        }
        .task {
            guard model == nil, let library = session.libraryStore else { return }
            model = session.makeLetterboxdImportModel(library: library)
        }
    }
}

private struct LetterboxdForm: View {
    @Environment(AppSession.self) private var session
    @Bindable var model: LetterboxdImportModel
    let profileID: String?
    let push: LetterboxdPushCoordinator?
    @State private var connection: ServerConnectionTest?

    private var canImport: Bool {
        model.settings.isEnabled && !model.settings.username.isEmpty && profileID?.isEmpty == false
    }

    var body: some View {
        Form {
            Section {
                TextField("Username", text: Binding(
                    get: { model.settings.username },
                    set: { var s = model.settings; s.username = $0; model.update(s) }))
                    .autocorrectionDisabled()
                Toggle("Import my ratings", isOn: Binding(
                    get: { model.settings.isEnabled },
                    set: { var s = model.settings; s.isEnabled = $0; model.update(s) }))
                importRow
                if let last = model.settings.lastImportAt {
                    Text("Last imported \(last.formatted(date: .abbreviated, time: .shortened))")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            } header: {
                Text("Your Letterboxd")
            } footer: {
                Text("Your public username. Ratings and your watchlist are read directly from Letterboxd.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    TextField("Seret server", text: Binding(
                        get: { model.settings.serverURL },
                        set: { var s = model.settings; s.serverURL = $0; model.update(s) }),
                              prompt: Text("192.168.1.179:8080"))
                        .autocorrectionDisabled()
                    Button("Test Connection") {
                        let test = session.makeServerConnectionTest(address: model.settings.serverURL)
                        connection = test
                        Task { await test.run() }
                    }
                    .disabled(model.settings.serverURL.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let connection { connectionStatus(connection) }
                if model.pendingPushes > 0 {
                    Label("\(model.pendingPushes) watch\(model.pendingPushes == 1 ? "" : "es") waiting to send",
                          systemImage: "tray.and.arrow.up")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let error = model.lastPushError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            } header: {
                Text("Diary and Watchlist Writes")
            } footer: {
                Text("Writes go through your Seret server, which is signed in to Letterboxd. If it can't be reached, they wait here and are sent later.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task { await model.refreshPushStatus(from: push) }
    }

    @ViewBuilder private var importRow: some View {
        switch model.phase {
        case .idle:
            Button("Import Now") { Task { await model.importNow(profileID: profileID) } }
                .disabled(!canImport)
        case .running(let done, let total):
            HStack(spacing: 10) {
                ProgressView(value: total > 0 ? Double(done) / Double(total) : nil)
                    .frame(width: 140)
                Text(total > 0 ? "Matching \(done) of \(total)…" : "Reading your profile…")
                    .foregroundStyle(.secondary)
            }
        case .finished(let summary):
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.written == 0 ? "Nothing new to fill in"
                                          : "Filled in \(summary.written) rating\(summary.written == 1 ? "" : "s")")
                if summary.conflicts > 0 {
                    Text("\(summary.conflicts) rated differently here — kept yours")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if summary.unresolved > 0 {
                    Text("\(summary.unresolved) not found on Letterboxd")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            Button("Import Again") { Task { await model.importNow(profileID: profileID) } }
                .disabled(!canImport)
        case .failed(let message):
            Text(message).foregroundStyle(.red)
            Button("Try Again") { Task { await model.importNow(profileID: profileID) } }
                .disabled(!canImport)
        }
    }

    @ViewBuilder private func connectionStatus(_ test: ServerConnectionTest) -> some View {
        switch test.result {
        case .untested:
            EmptyView()
        case .needsAddress:
            Text("Enter an address first").font(.footnote).foregroundStyle(.secondary)
        case .testing:
            Text("Testing…").font(.footnote).foregroundStyle(.secondary)
        case .reachable(let address):
            Label("Reached \(address)", systemImage: "checkmark.circle.fill")
                .font(.footnote).foregroundStyle(.green)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote).foregroundStyle(.red)
        }
    }
}

// MARK: - Playback

private struct PlaybackSettings: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        Form {
            Section {
                SubtitlePreview(preferences: session.subtitleSettings.preferences)
                    .listRowInsets(EdgeInsets())
                Picker("Size", selection: Binding(
                    get: { session.subtitleSettings.preferences.size },
                    set: { session.subtitleSettings.preferences.size = $0 })) {
                    ForEach(SubtitlePreferences.Size.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Picker("Font", selection: Binding(
                    get: { session.subtitleSettings.preferences.font },
                    set: { session.subtitleSettings.preferences.font = $0 })) {
                    ForEach(SubtitlePreferences.Font.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Picker("Colour", selection: Binding(
                    get: { session.subtitleSettings.preferences.color },
                    set: { session.subtitleSettings.preferences.color = $0 })) {
                    ForEach(SubtitlePreferences.Color.allCases, id: \.self) { Text($0.label).tag($0) }
                }
            } header: {
                Text("Subtitles")
            } footer: {
                Text("Applies to every film and show, from the next time playback starts.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section {
                Toggle("Autoplay trailers", isOn: Binding(
                    get: { session.trailerSettings.autoplayTrailers },
                    set: { session.trailerSettings.autoplayTrailers = $0 }))
            } header: {
                Text("Trailers")
            } footer: {
                Text("Play a muted trailer in a title's hero after a few seconds.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

/// The subtitle look over a dark still — white semibold with a soft blurred shadow and no box,
/// the style the owner approved — in the chosen size, font and colour.
struct SubtitlePreview: View {
    let preferences: SubtitlePreferences

    var body: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(colors: [Color(hex: 0x2A3440), Color(hex: 0x0E1116)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: 2) {
                Text("I think we should go back.")
                Text("אני חושב שכדאי שנחזור.")
            }
            .font(font)
            .foregroundStyle(color)
            .shadow(color: .black.opacity(0.85), radius: 3, x: 0, y: 1)
            .shadow(color: .black.opacity(0.5), radius: 8)
            .multilineTextAlignment(.center)
            .padding(.bottom, 18)
        }
        .frame(height: 150)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(8)
    }

    private var font: Font {
        let size = 18 * preferences.size.scale
        if let name = preferences.font.freetypeName {
            return .custom(name, size: size).weight(.semibold)
        }
        return .system(size: size, weight: .semibold)
    }

    private var color: Color {
        let rgb = preferences.color.rgb
        return Color(red: Double((rgb >> 16) & 0xFF) / 255, green: Double((rgb >> 8) & 0xFF) / 255,
                     blue: Double(rgb & 0xFF) / 255)
    }
}

// MARK: - About

private struct AboutSettings: View {
    var body: some View {
        VStack(spacing: 10) {
            SeretMark().frame(width: 64)
            Wordmark(hebrewSize: 34)
            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–")")
                .font(Theme.Typo.caption()).foregroundStyle(Theme.Palette.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
