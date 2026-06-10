import SwiftUI
import DebridUI
import DebridCore

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
                VStack(spacing: 40) {
                Text("Settings").font(.largeTitle.bold()).foregroundStyle(Theme.Palette.textPrimary)
                Text("Signed in to Real‑Debrid.").font(.title3).foregroundStyle(Theme.Palette.textSecondary)

                VStack(alignment: .leading, spacing: 16) {
                    Label("OpenSubtitles account", systemImage: "captions.bubble.fill")
                        .font(.title3.bold()).foregroundStyle(Theme.Palette.gold)
                    Text(model.isConnected
                         ? "Connected as \(model.username). Used to download Hebrew/English subtitles."
                         : "Add your free OpenSubtitles account to download subtitles during playback.")
                        .font(.callout).foregroundStyle(Theme.Palette.textSecondary)
                    TextField("Username", text: $model.username)
                        .textContentType(.username)
                    SecureField("Password", text: $model.password)
                        .textContentType(.password)
                    HStack(spacing: 20) {
                        Button("Save") { model.save() }
                        if model.isConnected {
                            Button("Remove", role: .destructive) { model.remove() }
                        }
                    }
                }
                .frame(maxWidth: 700)
                .padding(40)
                .background(Theme.Palette.surface1, in: RoundedRectangle(cornerRadius: 24))

                VStack(alignment: .leading, spacing: 16) {
                    Label("Subtitles", systemImage: "textformat.size")
                        .font(.title3.bold()).foregroundStyle(Theme.Palette.gold)
                    Text("Applies to every movie and show. Takes effect on the next playback.")
                        .font(.callout).foregroundStyle(Theme.Palette.textSecondary)
                    pillRow("Size", SubtitlePreferences.Size.allCases, label: { $0.label }, selected: subtitleSize)
                    pillRow("Font", SubtitlePreferences.Font.allCases, label: { $0.label }, selected: subtitleFont)
                    pillRow("Color", SubtitlePreferences.Color.allCases, label: { $0.label }, selected: subtitleColor)
                }
                .frame(maxWidth: 900)

                VStack(alignment: .leading, spacing: 16) {
                    Label("Trailers", systemImage: "play.rectangle.fill")
                        .font(.title3.bold()).foregroundStyle(Theme.Palette.gold)
                    Toggle("Autoplay trailers", isOn: Binding(
                        get: { session.trailerSettings.autoplayTrailers },
                        set: { session.trailerSettings.autoplayTrailers = $0 }))
                    Text("Play a muted trailer on a title's page automatically.")
                        .font(.callout).foregroundStyle(Theme.Palette.textSecondary)
                }
                .frame(maxWidth: 900)

                VStack(alignment: .leading, spacing: 16) {
                    Label("Profile", systemImage: "person.crop.circle.fill")
                        .font(.title3.bold()).foregroundStyle(Theme.Palette.gold)
                    if let name = session.activeProfiles?.activeProfile?.name {
                        Text("Watching as \(name).").font(.callout)
                            .foregroundStyle(Theme.Palette.textSecondary)
                    }
                    Text("Add a profile so each viewer gets their own Continue Watching and My List.")
                        .font(.callout).foregroundStyle(Theme.Palette.textSecondary)
                    Label(session.profilesSyncedViaICloud ? "Syncing via iCloud" : "On this device only",
                          systemImage: session.profilesSyncedViaICloud ? "checkmark.icloud.fill" : "icloud.slash")
                        .font(.callout)
                        .foregroundStyle(session.profilesSyncedViaICloud ? Theme.Palette.gold : Theme.Palette.textSecondary)
                    HStack(spacing: 24) {
                        if session.activeProfiles?.activeProfile != nil {
                            Button("Edit Profile") { editingActive = true }
                        }
                        Button("Manage Profiles") { showingProfiles = true }
                    }
                }
                .frame(maxWidth: 900)

                Button(role: .destructive) {
                    Task { await session.signOut() }
                } label: {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right").font(.title3)
                }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 80)
                .padding(.top, 20)
                .padding(.bottom, 80)
                .focusSection()      // let DOWN from the top nav bar move into the form
            }
        }
        .fullScreenCover(isPresented: $showingProfiles) {
            WhoIsWatchingScreen(onPicked: { showingProfiles = false })
                .environment(session)
        }
        .fullScreenCover(isPresented: $editingActive) {
            AddProfileScreen(editing: session.activeProfiles?.activeProfile).environment(session)
        }
    }

    /// A labelled row of focusable Gold-Glass pills (replaces the cramped `.segmented` picker that
    /// clipped longer labels like "Monospace" on tvOS). Pills size to their text, so nothing clips.
    @ViewBuilder
    private func pillRow<T: Hashable>(_ title: String, _ options: [T],
                                      label: @escaping (T) -> String,
                                      selected: Binding<T>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.callout.weight(.semibold)).foregroundStyle(Theme.Palette.textSecondary)
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
