import DebridCore
import DebridUI
import SwiftUI

struct SettingsView: View {
    @Environment(AppSession.self) private var session
    @State private var model = SettingsModel(
        secretStore: KeychainSecretStore(service: "com.solomons.seret.opensubtitles"))
    @State private var showingProfiles = false
    @State private var editingActive = false

    var body: some View {
        Form {
            Section("Account") {
                Label("Signed in to Real‑Debrid", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(Theme.Palette.textPrimary)
                Button(role: .destructive) {
                    Task { await session.signOut() }
                } label: {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
            .listRowBackground(Theme.Palette.surface1)

            Section {
                if session.activeProfiles?.activeProfile != nil {
                    Button { editingActive = true } label: {
                        Label("Edit Profile", systemImage: "pencil")
                            .foregroundStyle(Theme.Palette.textPrimary)
                    }
                }
                Button { showingProfiles = true } label: {
                    Label("Manage Profiles", systemImage: "person.2.crop.square.stack")
                        .foregroundStyle(Theme.Palette.textPrimary)
                }
                Label(session.profilesSyncedViaICloud ? "Syncing via iCloud" : "On this device only",
                      systemImage: session.profilesSyncedViaICloud ? "checkmark.icloud.fill" : "icloud.slash")
                    .foregroundStyle(session.profilesSyncedViaICloud ? Theme.Palette.gold : Theme.Palette.textSecondary)
            } header: {
                Text("Profile").foregroundStyle(Theme.Palette.gold)
            } footer: {
                if let name = session.activeProfiles?.activeProfile?.name {
                    Text("Watching as \(name). Add a profile so each viewer gets their own Continue Watching and My List.")
                        .font(.footnote).foregroundStyle(Theme.Palette.textSecondary)
                } else {
                    Text("Add a profile so each viewer gets their own Continue Watching and My List.")
                        .font(.footnote).foregroundStyle(Theme.Palette.textSecondary)
                }
            }
            .listRowBackground(Theme.Palette.surface1)

            Section {
                if model.isConnected {
                    Label("Signed in to OpenSubtitles", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(Theme.Palette.textPrimary)
                    Button(role: .destructive) { model.remove() } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } else {
                    NavigationLink {
                        OpenSubtitlesSignInView(model: model)
                    } label: {
                        Label("Sign in to OpenSubtitles", systemImage: "captions.bubble")
                            .foregroundStyle(Theme.Palette.textPrimary)
                    }
                }
            } header: {
                Text("OpenSubtitles").foregroundStyle(Theme.Palette.gold)
            } footer: {
                if model.isConnected {
                    Text("Connected as \(model.username). Used to download Hebrew/English subtitles.")
                        .font(.footnote).foregroundStyle(Theme.Palette.textSecondary)
                } else {
                    Text("Add your free OpenSubtitles account to download subtitles during playback.")
                        .font(.footnote).foregroundStyle(Theme.Palette.textSecondary)
                }
            }
            .listRowBackground(Theme.Palette.surface1)

            Section {
                if !session.traktConfigured {
                    Label("Not configured in this build", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Theme.Palette.textSecondary)
                } else if session.traktLinked {
                    Label("Linked to Trakt", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(Theme.Palette.textPrimary)
                    Button(role: .destructive) {
                        Task { await session.unlinkTrakt() }
                    } label: {
                        Label("Unlink", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } else {
                    NavigationLink {
                        TraktLinkView()
                    } label: {
                        Label("Link Trakt", systemImage: "arrow.triangle.2.circlepath")
                            .foregroundStyle(Theme.Palette.textPrimary)
                    }
                }
            } header: {
                Text("Trakt").foregroundStyle(Theme.Palette.gold)
            } footer: {
                Text(session.traktLinked
                     ? "Watched history, resume position, and ratings sync with Trakt."
                     : "Link Trakt to sync watched history, resume position, and ratings across devices.")
                    .font(.footnote).foregroundStyle(Theme.Palette.textSecondary)
            }
            .listRowBackground(Theme.Palette.surface1)

            Section {
                Picker("Size", selection: subtitleSize) {
                    ForEach(SubtitlePreferences.Size.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Picker("Font", selection: subtitleFont) {
                    ForEach(SubtitlePreferences.Font.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Picker("Color", selection: subtitleColor) {
                    ForEach(SubtitlePreferences.Color.allCases, id: \.self) { c in
                        HStack(spacing: Theme.Space.sm) {
                            Circle().fill(c.swatch).frame(width: 12, height: 12)
                            Text(c.label)
                        }.tag(c)
                    }
                }
            } header: {
                Text("Subtitles").foregroundStyle(Theme.Palette.gold)
            } footer: {
                Text("Applies to every movie and show. Takes effect the next time you start playback.")
                    .font(.footnote).foregroundStyle(Theme.Palette.textSecondary)
            }
            .listRowBackground(Theme.Palette.surface1)

            Section {
                Toggle("Autoplay trailers", isOn: Binding(
                    get: { session.trailerSettings.autoplayTrailers },
                    set: { session.trailerSettings.autoplayTrailers = $0 }))
            } header: {
                Text("Trailers").foregroundStyle(Theme.Palette.gold)
            } footer: {
                Text("Play a muted trailer on a title's page automatically.")
                    .font(.footnote).foregroundStyle(Theme.Palette.textSecondary)
            }
            .listRowBackground(Theme.Palette.surface1)

            Section {
                LabeledContent("Version", value: appVersion)
                    .foregroundStyle(Theme.Palette.textSecondary)
            } footer: {
                HStack(spacing: Theme.Space.sm) {
                    SeretMark(glow: false).frame(width: 16)
                    Text("Seret").font(Theme.Typo.label()).foregroundStyle(Theme.Palette.textTertiary)
                }
                .frame(maxWidth: .infinity).padding(.top, Theme.Space.lg)
            }
            .listRowBackground(Theme.Palette.surface1)
        }
        .scrollContentBackground(.hidden)
        .background(CanvasBackground())
        .tint(Theme.Palette.gold)
        .navigationTitle("Settings")
        .sheet(isPresented: $showingProfiles) {
            NavigationStack {
                WhoIsWatchingScreen(onPicked: { showingProfiles = false })
                    .environment(session)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showingProfiles = false }.tint(Theme.Palette.gold)
                        }
                    }
            }
        }
        .sheet(isPresented: $editingActive) {
            AddProfileScreen(editing: session.activeProfiles?.activeProfile).environment(session)
        }
    }

    // Bindings into the shared, persisted subtitle preferences.
    private var subtitleSize: Binding<SubtitlePreferences.Size> {
        Binding(get: { session.subtitleSettings.preferences.size },
                set: { session.subtitleSettings.preferences.size = $0 })
    }
    private var subtitleFont: Binding<SubtitlePreferences.Font> {
        Binding(get: { session.subtitleSettings.preferences.font },
                set: { session.subtitleSettings.preferences.font = $0 })
    }
    private var subtitleColor: Binding<SubtitlePreferences.Color> {
        Binding(get: { session.subtitleSettings.preferences.color },
                set: { session.subtitleSettings.preferences.color = $0 })
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }
}

private extension SubtitlePreferences.Color {
    /// SwiftUI swatch from the stored 0xRRGGBB value (kept out of DebridUI to keep it SwiftUI-free).
    var swatch: Color {
        Color(red: Double((rgb >> 16) & 0xFF) / 255, green: Double((rgb >> 8) & 0xFF) / 255,
              blue: Double(rgb & 0xFF) / 255)
    }
}
