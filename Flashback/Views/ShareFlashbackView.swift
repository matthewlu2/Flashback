//
//  ShareFlashbackView.swift
//  Flashback
//
//  Created by Claude on 6/7/26.
//

import SwiftUI

struct ShareFlashbackView: View {
    let flashback: Flashback
    let isOwner: Bool

    @Environment(\.dismiss) private var dismiss
    @StateObject private var friendsManager = FriendsManager.shared

    @State private var invite: FlashbackInvite?
    @State private var qrImage: UIImage?
    @State private var members: [MemberInfo] = []
    @State private var pendingRequests: [JoinRequestInfo] = []
    @State private var addedFriendIds: Set<UUID> = []
    @State private var isLoadingInvite = true

    private var inviteURLString: String {
        guard let token = invite?.token else { return "" }
        return InviteManager.shared.inviteURL(token: token).absoluteString
    }

    var body: some View {
        NavigationStack {
            List {
                inviteSection

                if isOwner && !pendingRequests.isEmpty {
                    requestsSection
                }

                if isOwner {
                    friendsSection
                }

                membersSection
            }
            .navigationTitle("Share")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await loadEverything() }
        }
    }

    // MARK: - Sections

    private var inviteSection: some View {
        Section("Invite") {
            if let qrImage {
                HStack {
                    Spacer()
                    Image(uiImage: qrImage)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 200, height: 200)
                        .padding(8)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    Spacer()
                }
                .listRowBackground(Color.clear)
            } else if isLoadingInvite {
                HStack { Spacer(); ProgressView(); Spacer() }
            }

            if !inviteURLString.isEmpty {
                Button {
                    UIPasteboard.general.string = inviteURLString
                } label: {
                    Label("Copy Link", systemImage: "link")
                }

                ShareLink(item: URL(string: inviteURLString)!) {
                    Label("Share Invite", systemImage: "square.and.arrow.up")
                }
            }

            Text("Anyone who opens this link can request to join. \(isOwner ? "You'll" : "The owner will") approve new members.")
                .font(.caption)
                .foregroundColor(.gray)
        }
    }

    private var requestsSection: some View {
        Section("Requests to Join") {
            ForEach(pendingRequests) { req in
                HStack(spacing: 12) {
                    AvatarView(urlPath: req.profile?.avatarUrl, name: req.displayName, size: 40)
                    Text(req.displayName).font(.subheadline.weight(.semibold))
                    Spacer()
                    Button {
                        Task { await approve(req) }
                    } label: {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2).foregroundColor(.green)
                    }
                    .buttonStyle(.plain)
                    Button {
                        Task { await deny(req) }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2).foregroundColor(.gray)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var friendsSection: some View {
        Section("Add Friends") {
            let memberIds = Set(members.map { $0.userId })
            let addable = friendsManager.friends.filter { !memberIds.contains($0.id) }
            if addable.isEmpty {
                Text("All your friends are already members.")
                    .font(.subheadline).foregroundColor(.gray)
            } else {
                ForEach(addable) { friend in
                    HStack(spacing: 12) {
                        AvatarView(urlPath: friend.avatarUrl, name: friend.displayName, size: 40)
                        Text(friend.displayName).font(.subheadline.weight(.semibold))
                        Spacer()
                        let added = addedFriendIds.contains(friend.id)
                        Button {
                            Task { await addFriend(friend) }
                        } label: {
                            Text(added ? "Added" : "Add")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(added ? .gray : .white)
                                .padding(.horizontal, 14).padding(.vertical, 7)
                                .background(added ? Color.gray.opacity(0.2) : Color.blue)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(added)
                    }
                }
            }
        }
    }

    private var membersSection: some View {
        Section("Members (\(members.count))") {
            ForEach(members) { member in
                HStack(spacing: 12) {
                    AvatarView(urlPath: member.profile?.avatarUrl, name: member.displayName, size: 40)
                    Text(member.displayName).font(.subheadline.weight(.semibold))
                    Spacer()
                    if member.role == .owner {
                        Text("Owner")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.gray)
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func loadEverything() async {
        // Load the invite + QR first and independently so they appear immediately,
        // while friends and members load concurrently in the background.
        async let inviteWork: Void = loadInvite()
        async let friendsWork: Void = friendsManager.refresh()
        async let membersWork: Void = reloadMembersAndRequests()
        _ = await (inviteWork, friendsWork, membersWork)
    }

    private func loadInvite() async {
        isLoadingInvite = true
        defer { isLoadingInvite = false }

        do {
            // Any member can create/share an invite (RLS permits it), so don't gate on isOwner —
            // gating here caused the QR/links to stay blank when isOwner hadn't resolved yet.
            let loaded = try await InviteManager.shared.inviteOrCreate(for: flashback.id)
            invite = loaded

            let urlString = InviteManager.shared.inviteURL(token: loaded.token).absoluteString
            qrImage = await InviteManager.makeQRCode(from: urlString)
        } catch {
            print("invite load error: \(error.localizedDescription)")
        }
    }

    private func reloadMembersAndRequests() async {
        members = (try? await FlashbackManager.shared.members(for: flashback.id)) ?? []
        if isOwner {
            pendingRequests = (try? await FlashbackManager.shared.pendingRequests(for: flashback.id)) ?? []
        }
    }

    private func approve(_ req: JoinRequestInfo) async {
        try? await FlashbackManager.shared.approve(requestId: req.request.id)
        await reloadMembersAndRequests()
    }

    private func deny(_ req: JoinRequestInfo) async {
        try? await FlashbackManager.shared.deny(requestId: req.request.id)
        await reloadMembersAndRequests()
    }

    private func addFriend(_ friend: PublicProfile) async {
        do {
            try await FlashbackManager.shared.addMember(friend.id, to: flashback.id)
            addedFriendIds.insert(friend.id)
            await reloadMembersAndRequests()
        } catch {
            print("addMember error: \(error.localizedDescription)")
        }
    }
}
