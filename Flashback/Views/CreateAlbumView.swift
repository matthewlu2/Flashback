//
//  CreateAlbumView.swift
//  Flashback
//
//  Created by Claude on 6/21/26.
//

import SwiftUI

/// Multi-step wizard for creating a new album (flashback):
/// Step 1 — pick a type, Step 2 — name it, Step 3 — invite friends.
struct CreateAlbumView: View {
    let onCreated: (Flashback) -> Void

    private enum Step: Int {
        case type
        case name
        case friends
    }

    @State private var step: Step = .type
    @State private var selectedType: AlbumType?
    @State private var name = ""
    @State private var selectedFriendIds: Set<UUID> = []
    @State private var isCreating = false
    @State private var errorMessage: String?

    @StateObject private var friendsManager = FriendsManager.shared
    @Environment(\.dismiss) private var dismiss

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .type: typeStep
                case .name: nameStep
                case .friends: friendsStep
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if step == .type {
                        Button("Cancel") { dismiss() }
                    } else {
                        Button("Back") { goBack() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    trailingButton
                }
            }
        }
    }

    private var navigationTitle: String {
        switch step {
        case .type: return "New Album"
        case .name: return "Name Album"
        case .friends: return "Invite Friends"
        }
    }

    @ViewBuilder
    private var trailingButton: some View {
        switch step {
        case .type:
            EmptyView()
        case .name:
            Button("Next") { step = .friends }
                .disabled(trimmedName.isEmpty)
        case .friends:
            if isCreating {
                ProgressView()
            } else {
                Button("Create") { create() }
            }
        }
    }

    // MARK: - Step 1: Type

    private var typeStep: some View {
        List {
            Section {
                ForEach(AlbumType.allCases) { type in
                    Button {
                        selectedType = type
                        step = .name
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: type.systemImage)
                                .font(.title2)
                                .frame(width: 36, height: 36)
                                .foregroundColor(.blue)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(type.title)
                                    .font(.body.weight(.semibold))
                                    .foregroundColor(.primary)
                                Text(type.subtitle)
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.gray)
                        }
                    }
                }
            } header: {
                Text("What kind of flashback is this?")
            }
        }
    }

    // MARK: - Step 2: Name

    private var nameStep: some View {
        Form {
            if let selectedType {
                Section {
                    Label(selectedType.title, systemImage: selectedType.systemImage)
                        .foregroundColor(.gray)
                }
            }

            Section {
                TextField("Album Name", text: $name)
            }
        }
    }

    // MARK: - Step 3: Friends

    private var friendsStep: some View {
        List {
            Section {
                let friends = friendsManager.friends
                if friends.isEmpty {
                    Text("No friends to invite yet.")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                } else {
                    ForEach(friends) { friend in
                        HStack(spacing: 12) {
                            AvatarView(urlPath: friend.avatarUrl, name: friend.displayName, size: 40)
                            Text(friend.displayName).font(.subheadline.weight(.semibold))
                            Spacer()
                            let added = selectedFriendIds.contains(friend.id)
                            Button {
                                toggle(friend.id)
                            } label: {
                                Text(added ? "Added" : "Add")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(added ? .gray : .white)
                                    .padding(.horizontal, 14).padding(.vertical, 7)
                                    .background(added ? Color.gray.opacity(0.2) : Color.blue)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            } header: {
                Text("Invite Friends (optional)")
            }

            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundColor(.red)
                }
            }
        }
        .task { await friendsManager.refresh() }
    }

    // MARK: - Actions

    private func toggle(_ id: UUID) {
        if selectedFriendIds.contains(id) {
            selectedFriendIds.remove(id)
        } else {
            selectedFriendIds.insert(id)
        }
    }

    private func goBack() {
        switch step {
        case .type: break
        case .name: step = .type
        case .friends: step = .name
        }
    }

    private func create() {
        guard !trimmedName.isEmpty else { return }
        isCreating = true
        errorMessage = nil

        Task {
            do {
                let flashback = try await FlashbackManager.shared.createFlashback(name: trimmedName)
                for id in selectedFriendIds {
                    try? await FlashbackManager.shared.addMember(id, to: flashback.id)
                }
                dismiss()
                onCreated(flashback)
            } catch {
                errorMessage = "Failed to create album: \(error.localizedDescription)"
                isCreating = false
            }
        }
    }
}
