import DebridCore
import DebridUI
import SwiftUI

struct SettingsView: View {
    @Environment(AppSession.self) private var session
    @State private var model = SettingsModel(
        secretStore: KeychainSecretStore(service: "com.solomons.seret.opensubtitles"))
    @State private var showingProfiles = false
    @State private var editingActive = false
    /// Built once and held, so an in-flight import survives redrawing this screen.
    @State private var letterboxdModel: LetterboxdImportModel?
#if DEBUG
    @Environment(\.uiPreviewStores) private var preview
#endif

    /// Nil until there is a library and a watch store to write into.
    private var letterboxd: LetterboxdImportModel? {
        letterboxdModel
    }

    var body: some View {
        GlassFormPage {
            // Each debrid account on its own: sign in to the other, sign out of one, where adds go.
            AccountsSection()

            // Profiles are switched off — nothing to manage here. See `ProfilesFeature`.
            if ProfilesFeature.isEnabled {
                GlassSection(title: "Profile", footer: profileFooter) {
                    if session.activeProfiles?.activeProfile != nil {
                        GlassButtonRow(title: "Edit Profile", systemImage: "pencil") { editingActive = true }
                    }
                    GlassButtonRow(title: "Manage Profiles", systemImage: "person.2.crop.square.stack") {
                        showingProfiles = true
                    }
                    GlassLabelRow(title: session.profilesSyncedViaICloud ? "Syncing via iCloud" : "On this device only",
                                  systemImage: session.profilesSyncedViaICloud ? "checkmark.icloud.fill" : "icloud.slash",
                                  tint: session.profilesSyncedViaICloud ? Theme.Palette.textPrimary
                                                                        : Theme.Palette.textSecondary)
                }
            }

            GlassSection(title: "OpenSubtitles",
                         footer: model.isConnected
                            ? "Connected as \(model.username). Used to download Hebrew/English subtitles."
                            : "Add your free OpenSubtitles account to download subtitles during playback.") {
                if model.isConnected {
                    GlassLabelRow(title: "Signed in to OpenSubtitles", systemImage: "checkmark.seal.fill",
                                  iconTint: Theme.Palette.textPrimary)
                    GlassButtonRow(title: "Sign Out", systemImage: "rectangle.portrait.and.arrow.right",
                                   destructive: true) { model.remove() }
                } else {
                    NavigationLink {
                        OpenSubtitlesSignInView(model: model)
                    } label: {
                        GlassLinkRow(title: "Sign in to OpenSubtitles", systemImage: "captions.bubble")
                    }
                    .buttonStyle(GlassRowPressStyle())
                }
            }

            GlassSection(title: "Subtitles",
                         footer: "Applies to every movie and show. Takes effect the next time you start playback.") {
                GlassPickerRow(title: "Size", selection: subtitleSize) {
                    ForEach(SubtitlePreferences.Size.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                GlassPickerRow(title: "Font", selection: subtitleFont) {
                    ForEach(SubtitlePreferences.Font.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                GlassPickerRow(title: "Color", selection: subtitleColor) {
                    ForEach(SubtitlePreferences.Color.allCases, id: \.self) { c in
                        Label { Text(c.label) } icon: { Image(systemName: "circle.fill").foregroundStyle(c.swatch) }
                            .tag(c)
                    }
                }
            }

            GlassSection(title: "Trailers", footer: "Play a muted trailer on a title's page automatically.") {
                GlassToggleRow(title: "Autoplay trailers", isOn: Binding(
                    get: { session.trailerSettings.autoplayTrailers },
                    set: { session.trailerSettings.autoplayTrailers = $0 }))
            }

            if let letterboxd {
                LetterboxdSettingsSection(model: letterboxd, profileID: session.activeProfileID,
                                          push: session.letterboxdPush)
            }

            GlassSection(title: "About") {
                GlassRow {
                    Text("Version")
                    Spacer(minLength: 0)
                    Text(appVersion).foregroundStyle(Theme.Palette.textSecondary)
                }
            }
            HStack(spacing: Theme.Space.sm) {
                SeretMark(glow: false).frame(width: 16)
                Text("Seret").font(Theme.Typo.label()).foregroundStyle(Theme.Palette.textTertiary)
            }
            .frame(maxWidth: .infinity)
        }
        .tint(Theme.Palette.focus)
        .navigationTitle("Settings")
        .task {
#if DEBUG
            if let fixture = preview?.letterboxdImport { letterboxdModel = fixture; return }
#endif
            guard letterboxdModel == nil, let library = session.libraryStore else { return }
            letterboxdModel = session.makeLetterboxdImportModel(library: library)
        }
        .sheet(isPresented: $showingProfiles) {
            NavigationStack {
                WhoIsWatchingScreen(onPicked: { showingProfiles = false })
                    .environment(session)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showingProfiles = false }.tint(Theme.Palette.focus)
                        }
                    }
            }
        }
        .sheet(isPresented: $editingActive) {
            AddProfileScreen(editing: session.activeProfiles?.activeProfile).environment(session)
        }
    }

    private var profileFooter: String {
        let pitch = "Add a profile so each viewer gets their own Continue Watching and My List."
        guard let name = session.activeProfiles?.activeProfile?.name else { return pitch }
        return "Watching as \(name). " + pitch
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
