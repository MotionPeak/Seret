import SwiftUI
import DebridUI
import DebridCore

/// Settings: one column of glass rows in a few sections, each row its name and current value.
///
/// Pressing a row makes the change — an On/Off row flips in place, a choice opens its own page
/// (pushed, so Menu comes back to the row). The pane on the left explains the focused row, which
/// is where every caption the old cards carried now lives.
///
/// Sections, in the order they are touched: Subtitles (how they look, where they come from),
/// Playback, Letterboxd, Profile (hidden while [`ProfilesFeature`] is off) and Account (the
/// debrid accounts, on their own page — see `AccountsPage`).
struct SettingsView: View {
    @Environment(AppSession.self) private var session
    @State private var model = SettingsModel(
        secretStore: KeychainSecretStore(service: "com.solomons.seret.opensubtitles"))
    @State private var showingProfiles = false
    @State private var editingActive = false
    /// Built once and held, so an in-flight import survives redrawing this screen.
    @State private var letterboxdModel: LetterboxdImportModel?
    @State private var help = SettingsHelp()

    var body: some View {
        SettingsPageLayout(title: "Settings") {
            // Its own view, so a focus move redraws the pane alone, not this whole list.
            RootHelpPane(help: help)
        } rows: {
            subtitles
            playback
            if let letterboxdModel {
                LetterboxdSettingsSection(model: letterboxdModel, profileID: session.activeProfileID,
                                          push: session.letterboxdPush)
            }
            // Profiles are switched off — nothing to manage. See `ProfilesFeature`.
            if ProfilesFeature.isEnabled { profile }
            account
        }
        .environment(help)
        .navigationDestination(for: SettingsPage.self) { page in
            destination(page)
        }
        .task {
            guard letterboxdModel == nil, let library = session.libraryStore else { return }
            letterboxdModel = session.makeLetterboxdImportModel(library: library)
        }
        .fullScreenCover(isPresented: $showingProfiles) {
            WhoIsWatchingScreen(onPicked: { showingProfiles = false }).environment(session)
        }
        .fullScreenCover(isPresented: $editingActive) {
            AddProfileScreen(editing: session.activeProfiles?.activeProfile).environment(session)
        }
    }

    // MARK: - Sections

    private var subtitles: some View {
        Group {
            SettingsSectionHeader(title: "Subtitles", first: true)
            SettingsLinkRow(title: "Size", value: preferences.size.label, page: .subtitleSize,
                            help: subtitleHelp("Size"))
            SettingsLinkRow(title: "Font", value: preferences.font.label, page: .subtitleFont,
                            help: subtitleHelp("Font"))
            SettingsLinkRow(title: "Color", value: preferences.color.label,
                            swatch: Color(hex: UInt(preferences.color.rgb)),
                            page: .subtitleColor, help: subtitleHelp("Color"))
            SettingsLinkRow(title: "Downloads",
                            value: model.isConnected ? model.username : "Not connected",
                            page: .openSubtitles,
                            help: SettingsHelpContent(
                                icon: "captions.bubble.fill", title: "Subtitle downloads",
                                text: model.isConnected
                                    ? "Connected to OpenSubtitles as \(model.username). Used to fetch Hebrew and English subtitles during playback."
                                    : "Sign in to OpenSubtitles to fetch Hebrew and English subtitles during playback."))
        }
    }

    private var playback: some View {
        Group {
            SettingsSectionHeader(title: "Playback")
            SettingsToggleRow(title: "Autoplay Trailers", isOn: Binding(
                get: { session.trailerSettings.autoplayTrailers },
                set: { session.trailerSettings.autoplayTrailers = $0 }),
                help: SettingsHelpContent(icon: "play.rectangle.fill", title: "Autoplay trailers",
                                          text: "Play a muted trailer on a title's page automatically."))
        }
    }

    private var profile: some View {
        let profileHelp = SettingsHelpContent(
            icon: "person.crop.circle.fill", title: "Profiles",
            text: "Each profile keeps its own Continue Watching and My List. "
                + (session.profilesSyncedViaICloud ? "Synced via iCloud." : "On this device only."))
        return Group {
            SettingsSectionHeader(title: "Profile")
            if let active = session.activeProfiles?.activeProfile {
                SettingsRow(title: "Edit Profile", value: active.name, help: profileHelp) {
                    editingActive = true
                }
            }
            SettingsRow(title: "Manage Profiles",
                        value: session.profilesSyncedViaICloud ? "iCloud" : "This device",
                        help: profileHelp) {
                showingProfiles = true
            }
        }
    }

    private var account: some View {
        Group {
            SettingsSectionHeader(title: "Account")
            SettingsLinkRow(title: "Accounts", value: signedInSummary, page: .accounts,
                            help: SettingsHelpContent(
                                icon: "person.badge.key.fill", title: "Accounts",
                                text: "Seret streams directly from your Real‑Debrid and TorBox accounts. "
                                    + "Sign in or out of each, and choose where new titles go."))
            SettingsRow(title: "Sign Out of All Accounts", destructive: true,
                        help: SettingsHelpContent(
                            icon: "rectangle.portrait.and.arrow.right", title: "Sign out of all accounts",
                            text: "Clears every Real‑Debrid and TorBox sign-in from this Apple TV. You'll need to sign in again to watch.")) {
                Task { await session.signOut() }
            }
        }
    }

    /// "Real-Debrid · TorBox" — the accounts this Apple TV is signed in to.
    private var signedInSummary: String {
        session.signedInProviders.map(\.displayName).joined(separator: " · ")
    }

    // MARK: - Pages

    @ViewBuilder private func destination(_ page: SettingsPage) -> some View {
        switch page {
        case .subtitleSize:
            SettingsChoicePage(title: "Subtitle Size", note: Self.subtitleNote,
                               options: SubtitlePreferences.Size.allCases, label: { $0.label },
                               selection: subtitleSize,
                               sample: { var p = preferences; p.size = $0; return p })
        case .subtitleFont:
            SettingsChoicePage(title: "Subtitle Font", note: Self.subtitleNote,
                               options: SubtitlePreferences.Font.allCases, label: { $0.label },
                               selection: subtitleFont,
                               sample: { var p = preferences; p.font = $0; return p })
        case .subtitleColor:
            SettingsChoicePage(title: "Subtitle Color", note: Self.subtitleNote,
                               options: SubtitlePreferences.Color.allCases, label: { $0.label },
                               selection: subtitleColor,
                               swatch: { Color(hex: UInt($0.rgb)) },
                               sample: { var p = preferences; p.color = $0; return p })
        case .openSubtitles:
            OpenSubtitlesPage(model: model)
        case .accounts:
            AccountsPage(session: session)
        }
    }

    private static let subtitleNote = "Applies to every movie and show, from the next playback on."

    private func subtitleHelp(_ title: String) -> SettingsHelpContent {
        SettingsHelpContent(icon: "captions.bubble.fill", title: "Subtitle \(title.lowercased())",
                            text: Self.subtitleNote, showsSubtitleSample: true)
    }

    // MARK: - Bindings into the shared, persisted subtitle preferences

    private var preferences: SubtitlePreferences { session.subtitleSettings.preferences }

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
}

/// The root page's pane, reading the focused row's help itself — see `SettingsView.body`.
private struct RootHelpPane: View {
    @Environment(AppSession.self) private var session
    let help: SettingsHelp

    var body: some View {
        SettingsHelpPane(content: help.current, subtitleStyle: session.subtitleSettings.preferences)
    }
}
