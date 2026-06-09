import DebridCore
import DebridUI
import SwiftUI

/// tvOS profile editor — creates a new profile, or edits an existing one when `editing` is set.
/// A real focusable form (name + color + avatar), with Create/Save reachable above the grid.
struct AddProfileScreen: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var color: String
    @State private var avatar: String
    @FocusState private var focusedAvatar: String?
    @FocusState private var focusedColor: String?
    @State private var showingDeleteConfirm = false

    private let editing: ProfileDTO?

    init(editing: ProfileDTO? = nil) {
        self.editing = editing
        _name = State(initialValue: editing?.name ?? "")
        _color = State(initialValue: editing?.colorTag ?? "gold")
        _avatar = State(initialValue: editing.map { ProfileAvatars.token($0.avatar) }
                        ?? (ProfileAvatars.all.first ?? ProfileAvatars.fallback))
    }

    private let columns = [GridItem(.adaptive(minimum: 130), spacing: 28)]
    private let palette = ["gold", "blue", "green", "red", "purple"]
    private var count: Int { session.activeProfiles?.roster.count ?? 0 }
    private var canDelete: Bool { editing != nil && count > 1 }
    private var finalName: String {
        let t = name.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? (editing?.name ?? "Profile \(count + 1)") : t
    }

    var body: some View {
        ZStack {
            CanvasBackground()
            ScrollView {
                VStack(spacing: 32) {
                    VStack(spacing: 24) {
                        Text(editing == nil ? "Add Profile" : "Edit Profile")
                            .screenTitle().foregroundStyle(Theme.Palette.textPrimary)
                        ProfileAvatarImage(token: avatar, diameter: 170, colorTag: color)
                            .goldGlow(20, opacity: 0.25)
                        TextField("Name (optional)", text: $name)
                            .frame(maxWidth: 560).font(.title3)
                            .padding(.vertical, 10).padding(.horizontal, 24)
                            .background(Theme.Palette.surface1, in: RoundedRectangle(cornerRadius: 14))
                        colorRow
                        HStack(spacing: 24) {
                            Button("Cancel") { dismiss() }
                            Button(editing == nil ? "Create" : "Save") { save() }
                                .buttonStyle(.borderedProminent).tint(Theme.Palette.gold)
                            if canDelete {
                                Button("Delete", role: .destructive) { showingDeleteConfirm = true }
                                    .confirmationDialog(
                                        "Delete \(editing?.name ?? "this profile")?",
                                        isPresented: $showingDeleteConfirm, titleVisibility: .visible) {
                                        Button("Delete Profile", role: .destructive) {
                                            let id = editing!.id
                                            Task { await session.deleteProfile(id); dismiss() }
                                        }
                                        Button("Cancel", role: .cancel) {}
                                    } message: {
                                        Text("This permanently removes this profile, its Continue Watching, and its My List. This can't be undone.")
                                    }
                            }
                        }
                        .font(.title3)
                    }

                    Text("Pick an avatar").cardTitle().foregroundStyle(Theme.Palette.textSecondary)
                    LazyVGrid(columns: columns, spacing: 28) {
                        ForEach(ProfileAvatars.all, id: \.self) { e in
                            Button { avatar = e } label: {
                                ProfileAvatarImage(token: e, diameter: 104, colorTag: color)
                                    .overlay(Circle().strokeBorder(
                                        avatar == e ? Theme.Palette.gold : .clear, lineWidth: 5))
                            }
                            .buttonStyle(BareButtonStyle())
                            .focusEffectDisabled()
                            .focused($focusedAvatar, equals: e)
                            .scaleEffect(focusedAvatar == e ? Theme.Anim.heroFocusScale : 1)
                            .animation(Theme.Anim.heroSpring, value: focusedAvatar)
                        }
                    }
                    .padding(.horizontal, 80)
                }
                .padding(60)
            }
        }
    }

    private var colorRow: some View {
        HStack(spacing: 22) {
            ForEach(palette, id: \.self) { tag in
                Button { color = tag } label: {
                    Circle().fill(Theme.Palette.color(for: tag)).frame(width: 56, height: 56)
                        .overlay(Circle().strokeBorder(color == tag ? Theme.Palette.textPrimary : .clear, lineWidth: 4))
                }
                .buttonStyle(BareButtonStyle())
                .focusEffectDisabled()
                .focused($focusedColor, equals: tag)
                .scaleEffect(focusedColor == tag ? 1.18 : 1)
                .animation(Theme.Anim.focus, value: focusedColor)
            }
        }
    }

    private func save() {
        let n = finalName, c = color, a = avatar
        if let editing {
            Task { await session.updateProfile(id: editing.id, name: n, colorTag: c, avatar: a); dismiss() }
        } else {
            Task { await session.createProfile(name: n, colorTag: c, avatar: a); dismiss() }
        }
    }
}
