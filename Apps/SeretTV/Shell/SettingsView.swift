import SwiftUI
import DebridUI
import DebridCore

/// Settings as one column of identical cards.
///
/// Four sections, ordered by how often they are touched: how subtitles look, where they come from,
/// who is watching, and the account. Trakt is gone — watch state is kept on the device and synced
/// through iCloud, so the card was offering to mirror to a service the app no longer depends on.
struct SettingsView: View {
    @Environment(AppSession.self) private var session
    @State private var model = SettingsModel(
        secretStore: KeychainSecretStore(service: "com.solomons.seret.opensubtitles"))
    @State private var showingProfiles = false
    @State private var editingActive = false

    var body: some View {
        ZStack {
            CanvasBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header
                    subtitleAppearance
                    OpenSubtitlesSection(model: model)
                    playback
                    profile
                    account
                }
                .frame(maxWidth: .infinity)          // centre the fixed-width column
                .padding(.top, 40)
                .padding(.bottom, 90)
                .focusSection()                      // let DOWN from the nav rail enter the form
            }
        }
        .fullScreenCover(isPresented: $showingProfiles) {
            WhoIsWatchingScreen(onPicked: { showingProfiles = false }).environment(session)
        }
        .fullScreenCover(isPresented: $editingActive) {
            AddProfileScreen(editing: session.activeProfiles?.activeProfile).environment(session)
        }
    }

    private var header: some View {
        Text("Settings")
            .font(.largeTitle.bold())
            .foregroundStyle(Theme.Palette.textPrimary)
            .frame(width: SettingsCard<EmptyView>.width, alignment: .leading)
    }

    // MARK: - Sections

    private var subtitleAppearance: some View {
        SettingsCard(title: "Subtitles", icon: "textformat.size") {
            Text("Applies to every movie and show, from the next playback on.")
                .settingsCaption()
            pillRow("Size", SubtitlePreferences.Size.allCases, label: { $0.label }, selected: subtitleSize)
            pillRow("Font", SubtitlePreferences.Font.allCases, label: { $0.label }, selected: subtitleFont)
            pillRow("Color", SubtitlePreferences.Color.allCases, label: { $0.label }, selected: subtitleColor)
        }
    }

    private var playback: some View {
        SettingsCard(title: "Playback", icon: "play.rectangle.fill") {
            Toggle("Autoplay trailers", isOn: Binding(
                get: { session.trailerSettings.autoplayTrailers },
                set: { session.trailerSettings.autoplayTrailers = $0 }))
            Text("Play a muted trailer on a title's page automatically.")
                .settingsCaption()
        }
    }

    private var profile: some View {
        SettingsCard(title: "Profile", icon: "person.crop.circle.fill") {
            if let name = session.activeProfiles?.activeProfile?.name {
                SettingsStatus(text: "Watching as \(name)", good: true)
            }
            SettingsStatus(text: session.profilesSyncedViaICloud ? "Synced via iCloud"
                                                                 : "On this device only",
                           good: session.profilesSyncedViaICloud)
            Text("Each profile keeps its own Continue Watching and My List.")
                .settingsCaption()
            HStack(spacing: 24) {
                if session.activeProfiles?.activeProfile != nil {
                    Button("Edit Profile") { editingActive = true }
                }
                Button("Manage Profiles") { showingProfiles = true }
            }
        }
    }

    private var account: some View {
        SettingsCard(title: "Account", icon: "person.badge.key.fill") {
            SettingsStatus(text: "Signed in to Real‑Debrid", good: true)
            Text("Seret streams directly from your Real‑Debrid account. Signing out clears the token from this Apple TV.")
                .settingsCaption()
            Button(role: .destructive) {
                Task { await session.signOut() }
            } label: {
                Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
            }
        }
    }

    // MARK: - Controls

    /// A labelled row of focusable Gold-Glass pills (a `.segmented` picker clips longer labels like
    /// "Monospace" on tvOS). Pills size to their text, so nothing clips.
    @ViewBuilder
    private func pillRow<T: Hashable>(_ title: String, _ options: [T],
                                      label: @escaping (T) -> String,
                                      selected: Binding<T>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.seret(.callout, .semibold)).foregroundStyle(Theme.Palette.textSecondary)
            HStack(spacing: 14) {
                ForEach(options, id: \.self) { opt in
                    Button(label(opt)) { selected.wrappedValue = opt }
                        .buttonStyle(SeretPillStyle(selected: selected.wrappedValue == opt))
                        .fixedSize(horizontal: true, vertical: false)   // one line — never wrap "Rounded"
                }
            }
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
}
