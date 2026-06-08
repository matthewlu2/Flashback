//
//  FriendsView.swift
//  Flashback
//
//  Created by Claude on 6/7/26.
//

import SwiftUI

struct FriendsView: View {
    @StateObject private var manager = FriendsManager.shared
    @State private var showingAddFriends = false

    var body: some View {
        List {
            if !manager.incomingRequests.isEmpty {
                Section("Friend Requests") {
                    ForEach(manager.incomingRequests) { request in
                        HStack(spacing: 12) {
                            AvatarView(urlPath: request.profile.avatarUrl, name: request.profile.displayName, size: 44)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(request.profile.displayName)
                                    .font(.subheadline.weight(.semibold))
                                if let fullName = request.profile.fullName, !fullName.isEmpty {
                                    Text(fullName).font(.caption).foregroundColor(.gray)
                                }
                            }
                            Spacer()
                            Button {
                                Task { try? await manager.accept(request.friendship) }
                            } label: {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(.green)
                            }
                            .buttonStyle(.plain)
                            Button {
                                Task { try? await manager.decline(request.friendship) }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(.gray)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            Section("Friends") {
                if manager.friends.isEmpty {
                    Text("No friends yet. Tap the + to add some.")
                        .foregroundColor(.gray)
                        .font(.subheadline)
                } else {
                    ForEach(manager.friends) { friend in
                        HStack(spacing: 12) {
                            AvatarView(urlPath: friend.avatarUrl, name: friend.displayName, size: 44)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(friend.displayName)
                                    .font(.subheadline.weight(.semibold))
                                if let fullName = friend.fullName, !fullName.isEmpty {
                                    Text(fullName).font(.caption).foregroundColor(.gray)
                                }
                            }
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                Task { try? await manager.removeFriend(friend.id) }
                            } label: {
                                Label("Remove", systemImage: "person.badge.minus")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Friends")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAddFriends = true
                } label: {
                    Image(systemName: "person.badge.plus")
                }
            }
        }
        .sheet(isPresented: $showingAddFriends) {
            AddFriendsView()
        }
        .refreshable {
            await manager.refresh()
        }
        .task {
            await manager.refresh()
        }
    }
}

// MARK: - Add Friends

struct AddFriendsView: View {
    @StateObject private var manager = FriendsManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var results: [PublicProfile] = []
    @State private var isSearching = false
    @State private var sentIds: Set<UUID> = []

    @State private var contactMatches: [PublicProfile] = []
    @State private var isMatching = false
    @State private var didRunContacts = false

    var body: some View {
        NavigationStack {
            List {
                Section("Search by username") {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundColor(.gray)
                        TextField("Username", text: $query)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onSubmit { runSearch() }
                    }
                    if isSearching {
                        ProgressView()
                    }
                    ForEach(results) { profile in
                        friendRow(profile)
                    }
                }

                Section("From contacts") {
                    if !didRunContacts {
                        Button {
                            runContactMatch()
                        } label: {
                            Label("Find friends from contacts", systemImage: "person.crop.circle.badge.plus")
                        }
                    }
                    if isMatching {
                        ProgressView()
                    }
                    if didRunContacts && contactMatches.isEmpty && !isMatching {
                        Text("No contacts found on Flashback.")
                            .foregroundColor(.gray)
                            .font(.subheadline)
                    }
                    ForEach(contactMatches) { profile in
                        friendRow(profile)
                    }
                }
            }
            .navigationTitle("Add Friends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: query) { _, _ in
                runSearch()
            }
        }
    }

    private func friendRow(_ profile: PublicProfile) -> some View {
        HStack(spacing: 12) {
            AvatarView(urlPath: profile.avatarUrl, name: profile.displayName, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.displayName).font(.subheadline.weight(.semibold))
                if let fullName = profile.fullName, !fullName.isEmpty {
                    Text(fullName).font(.caption).foregroundColor(.gray)
                }
            }
            Spacer()
            let isSent = sentIds.contains(profile.id)
            Button {
                Task {
                    try? await manager.sendRequest(to: profile.id)
                    sentIds.insert(profile.id)
                }
            } label: {
                Text(isSent ? "Requested" : "Add")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(isSent ? .gray : .white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(isSent ? Color.gray.opacity(0.2) : Color.blue)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isSent)
        }
    }

    private func runSearch() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            results = []
            return
        }
        isSearching = true
        Task {
            defer { isSearching = false }
            results = (try? await manager.searchByUsername(trimmed)) ?? []
        }
    }

    private func runContactMatch() {
        didRunContacts = true
        isMatching = true
        Task {
            defer { isMatching = false }
            let onboarding = OnboardingManager()
            await onboarding.requestContactsAndMatch()
            contactMatches = onboarding.discovered
        }
    }
}
