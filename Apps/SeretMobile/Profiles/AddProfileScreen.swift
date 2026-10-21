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
        _color = State(initialValue: editing?.colorTag ?? Theme.Palette.defaultColorTag)
        _avatar = State(initialValue: editing.map { ProfileAvatars.token($0.avatar) }
                        ?? (ProfileAvatars.all.first ?? ProfileAvatars.fallback))
    }

    private let columns = [GridItem(.adaptive(minimum: 60), spacing: 12)]
    private let palette = [Theme.Palette.defaultColorTag, "blue", "green", "red", "purple"]
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
                GlassFormPage {
                    ProfileAvatarImage(token: avatar, diameter: 120, colorTag: color)
                        .shadow(color: Theme.Palette.color(for: color).opacity(0.45), radius: 16, y: 4)
                        .frame(maxWidth: .infinity)
                        .padding(.top, Theme.Space.sm)

                    GlassSection(title: "Name") {
                        GlassField(label: "Profile name", text: $name, prompt: "Optional", plain: false)
                    }

                    GlassSection(title: "Color") {
                        GlassRow {
                            ForEach(palette, id: \.self) { tag in
                                Button { color = tag } label: {
                                    Circle().fill(Theme.Palette.color(for: tag)).frame(width: 34, height: 34)
                                        .overlay(Circle().strokeBorder(
                                            color == tag ? Theme.Palette.textPrimary : .clear, lineWidth: 3))
                                        .padding(2)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(tag.capitalized)
                                .accessibilityAddTraits(color == tag ? .isSelected : [])
                            }
                            Spacer(minLength: 0)
                        }
                    }

                    GlassSection(title: "Avatar") {
                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(ProfileAvatars.all, id: \.self) { e in
                                Button { avatar = e } label: {
                                    ProfileAvatarImage(token: e, diameter: 56, colorTag: color)
                                        .overlay(Circle().strokeBorder(
                                            avatar == e ? Theme.Palette.focus : .clear, lineWidth: 3))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(Theme.Space.lg)
                    }

                    if canDelete {
                        GlassSection {
                            GlassButtonRow(title: "Delete Profile", systemImage: "trash", destructive: true) {
                                let id = editing!.id
                                Task { await session.deleteProfile(id); dismiss() }
                            }
                        }
                    }
                }
            }
            .navigationTitle(editing == nil ? "Add Profile" : "Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.tint(Theme.Palette.focus)
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
                    .tint(Theme.Palette.focus)
                }
            }
        }
    }
}
