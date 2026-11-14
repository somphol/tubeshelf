import SwiftUI
import TubeShelfCore

/// Manage the shelves on this Mac: switch, rename, add from a backup, or move one
/// to the Trash. Every profile is an isolated folder, so nothing here can leak
/// videos between shelves.
struct ProfileManagerView: View {
    let model: AppModel

    @Environment(\.dismiss) private var dismiss
    @State private var counts: [UUID: Int] = [:]
    @State private var hovering: UUID?
    @State private var dialog: Dialog?
    @State private var nameText = ""

    private enum Dialog: Identifiable {
        case rename(UUID, String)
        case delete(UUID, String)
        case create

        var id: String {
            switch self {
            case .rename(let id, _): "rename-\(id)"
            case .delete(let id, _): "delete-\(id)"
            case .create: "create"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)
            list
            Divider().opacity(0.4)
            footer
        }
        .frame(width: 500, height: 460)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear(perform: loadCounts)
        .alert(dialogTitle, isPresented: Binding(
            get: { dialog != nil },
            set: { if !$0 { dialog = nil } }
        )) {
            switch dialog {
            case .rename(let id, _):
                TextField("Profile name", text: $nameText)
                Button("Cancel", role: .cancel) { dialog = nil }
                Button("Rename") {
                    model.renameProfile(id, to: nameText)
                    dialog = nil
                }
            case .delete(let id, _):
                Button("Cancel", role: .cancel) { dialog = nil }
                Button("Move to Trash", role: .destructive) {
                    model.deleteProfile(id)
                    dialog = nil
                    loadCounts()
                }
                .disabled(model.profiles.count <= 1)
            case .create:
                TextField("Profile name", text: $nameText)
                Button("Cancel", role: .cancel) { dialog = nil }
                Button("Create") {
                    model.createEmptyProfile(named: nameText)
                    dialog = nil
                    loadCounts()
                }
            case .none:
                EmptyView()
            }
        } message: {
            Text(dialogMessage)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Profiles")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                Text("\(model.profiles.count) shelves on this Mac · each one is a separate folder")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Done") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(model.profiles) { profile in
                    row(profile)
                }
            }
            .padding(.vertical, 6)
        }
        .frame(maxHeight: .infinity)
    }

    private func row(_ profile: Profile) -> some View {
        let isActive = profile.id == model.activeProfileID
        return HStack(spacing: 10) {
            Monogram(name: profile.name, size: 26)

            Button {
                model.switchProfile(profile.id)
                dismiss()
            } label: {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(profile.name)
                            .font(.system(size: 12.5, weight: isActive ? .semibold : .medium))
                            .lineLimit(1)
                        if isActive {
                            Text("CURRENT")
                                .font(.system(size: 8, weight: .bold))
                                .tracking(0.6)
                                .foregroundStyle(Theme.accent)
                        }
                    }
                    Text(profile.subtitle)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text(counts[profile.id].map { "\($0) video\($0 == 1 ? "" : "s")" } ?? "—")
                .font(.system(size: 10.5))
                .monospacedDigit()
                .foregroundStyle(.secondary)

            Menu {
                Button("Switch to this profile") {
                    model.switchProfile(profile.id)
                    dismiss()
                }
                .disabled(isActive)
                Divider()
                Button("Rename…") {
                    nameText = profile.name
                    dialog = .rename(profile.id, profile.name)
                }
                Button("Add a profile from a backup…") {
                    BackupActions.importProfile(model)
                    dismiss()
                }
                Divider()
                Button("Move to Trash", role: .destructive) {
                    dialog = .delete(profile.id, profile.name)
                }
                .disabled(model.profiles.count <= 1)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 22)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 26)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(hovering == profile.id ? Color.primary.opacity(0.05) : Color.clear)
                .padding(.horizontal, 8)
        )
        .onHover { inside in
            hovering = inside ? profile.id : (hovering == profile.id ? nil : hovering)
        }
        .contextMenu {
            Button("Rename…") {
                nameText = profile.name
                dialog = .rename(profile.id, profile.name)
            }
            Button("Move to Trash", role: .destructive) {
                dialog = .delete(profile.id, profile.name)
            }
            .disabled(model.profiles.count <= 1)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button("Add from Backup…") {
                BackupActions.importProfile(model)
                dismiss()
            }
            .controlSize(.small)

            Button("New Empty Profile…") {
                nameText = "New Shelf"
                dialog = .create
            }
            .controlSize(.small)

            Spacer()

            Text("Deleted profiles go to the Trash, never straight to gone.")
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 11)
    }

    private var dialogTitle: String {
        switch dialog {
        case .rename: "Rename profile"
        case .delete: "Move profile to the Trash?"
        case .create: "New empty profile"
        case nil: ""
        }
    }

    private var dialogMessage: String {
        switch dialog {
        case .rename:
            return "Only the name changes. The shelf and its folder stay put."
        case .delete(let id, let name):
            let count = counts[id] ?? 0
            return "“\(name)” holds \(count) video\(count == 1 ? "" : "s"). The folder moves to the Trash and can be restored from there."
        case .create:
            return "A separate, empty shelf. Your current profile is not changed."
        case nil:
            return ""
        }
    }

    private func loadCounts() {
        var loaded: [UUID: Int] = [:]
        for profile in model.profiles {
            loaded[profile.id] = (try? model.profileStore.libraryStore(for: profile).load().count) ?? 0
        }
        counts = loaded
    }
}
