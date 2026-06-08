import DebridCore
import DebridUI
import SwiftUI

/// iOS Add-Profile sheet — name + emoji avatar picker. Creating returns to the picker.
struct AddProfileScreen: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var avatar = ProfileAvatars.all.first ?? ProfileAvatars.fallback

    private let columns = [GridItem(.adaptive(minimum: 64), spacing: 14)]
    private let palette = ["gold", "blue", "green", "red", "purple"]
    private var color: String { palette[(session.activeProfiles?.roster.count ?? 0) % palette.count] }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        NavigationStack {
            ZStack {
                CanvasBackground()
                ScrollView {
                    VStack(spacing: 28) {
                        ZStack {
                            Circle().fill(Theme.Palette.color(for: color)).frame(width: 120, height: 120)
                            Text(avatar).font(.system(size: 64))
                        }
                        .padding(.top, 12)

                        TextField("Name", text: $name)
                            .textFieldStyle(.roundedBorder)
                            .padding(.horizontal, 24)

                        Text("Pick an avatar").font(Theme.Typo.headline())
                            .foregroundStyle(Theme.Palette.textSecondary)
                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(ProfileAvatars.all, id: \.self) { e in
                                Button { avatar = e } label: {
                                    Text(e).font(.system(size: 34))
                                        .frame(width: 60, height: 60)
                                        .background(avatar == e ? Theme.Palette.gold.opacity(0.30)
                                                                : Theme.Palette.surface1, in: Circle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 24)
                    }
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle("Add Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.tint(Theme.Palette.gold)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Create") {
                        guard !trimmedName.isEmpty else { return }
                        Task {
                            await session.createProfile(name: trimmedName, colorTag: color, avatar: avatar)
                            dismiss()
                        }
                    }
                    .disabled(trimmedName.isEmpty)
                    .tint(Theme.Palette.gold)
                }
            }
        }
    }
}
