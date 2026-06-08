import DebridCore
import DebridUI
import SwiftUI

/// iOS profile editor sheet — creates a new profile, or edits an existing one when `editing` is set
/// (name + color + avatar, plus Delete). Returns to the picker on save.
struct AddProfileScreen: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var color: String
    @State private var avatar: String

    private let editing: ProfileDTO?

    init(editing: ProfileDTO? = nil) {
        self.editing = editing
        _name = State(initialValue: editing?.name ?? "")
        _color = State(initialValue: editing?.colorTag ?? "gold")
        _avatar = State(initialValue: editing.map { ProfileAvatars.token($0.avatar) }
                        ?? (ProfileAvatars.all.first ?? ProfileAvatars.fallback))
    }

    private let columns = [GridItem(.adaptive(minimum: 64), spacing: 14)]
    private let palette = ["gold", "blue", "green", "red", "purple"]
    private var count: Int { session.activeProfiles?.roster.count ?? 0 }
    private var canDelete: Bool { editing != nil && count > 1 }
    private var finalName: String {
        let t = name.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? (editing?.name ?? "Profile \(count + 1)") : t
    }

    var body: some View {
        NavigationStack {
            ZStack {
                CanvasBackground()
                ScrollView {
                    VStack(spacing: 24) {
                        ProfileAvatarImage(token: avatar, diameter: 120, colorTag: color)
                            .padding(.top, 12)

                        TextField("Name (optional)", text: $name)
                            .textFieldStyle(.roundedBorder)
                            .padding(.horizontal, 24)

                        HStack(spacing: 16) {
                            ForEach(palette, id: \.self) { tag in
                                Button { color = tag } label: {
                                    Circle().fill(Theme.Palette.color(for: tag)).frame(width: 34, height: 34)
                                        .overlay(Circle().strokeBorder(
                                            color == tag ? Theme.Palette.textPrimary : .clear, lineWidth: 3))
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Text("Pick an avatar").font(Theme.Typo.headline())
                            .foregroundStyle(Theme.Palette.textSecondary)
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(ProfileAvatars.all, id: \.self) { e in
                                Button { avatar = e } label: {
                                    ProfileAvatarImage(token: e, diameter: 60, colorTag: color)
                                        .overlay(Circle().strokeBorder(
                                            avatar == e ? Theme.Palette.gold : .clear, lineWidth: 3))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 24)

                        if canDelete {
                            Button(role: .destructive) {
                                let id = editing!.id
                                Task { await session.deleteProfile(id); dismiss() }
                            } label: {
                                Label("Delete Profile", systemImage: "trash")
                            }
                            .padding(.top, 8)
                        }
                    }
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle(editing == nil ? "Add Profile" : "Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.tint(Theme.Palette.gold)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(editing == nil ? "Create" : "Save") {
                        let n = finalName, c = color, a = avatar
                        Task {
                            if let editing {
                                await session.updateProfile(id: editing.id, name: n, colorTag: c, avatar: a)
                            } else {
                                await session.createProfile(name: n, colorTag: c, avatar: a)
                            }
                            dismiss()
                        }
                    }
                    .tint(Theme.Palette.gold)
                }
            }
        }
    }
}
