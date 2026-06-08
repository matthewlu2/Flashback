//
//  FriendsManager.swift
//  Flashback
//
//  Created by Claude on 6/7/26.
//

import SwiftUI
import Supabase
import Combine

/// A friend request the current user has received, paired with the requester's profile.
struct IncomingFriendRequest: Identifiable {
    let friendship: Friendship
    let profile: PublicProfile
    var id: UUID { friendship.id }
}

@MainActor
class FriendsManager: ObservableObject {
    static let shared = FriendsManager()

    @Published var friends: [PublicProfile] = []
    @Published var incomingRequests: [IncomingFriendRequest] = []
    @Published var outgoingRequestIds: Set<UUID> = []
    @Published var isLoading = false

    private init() {}

    /// Clears cached friend state when the authenticated user changes.
    func reset() {
        friends = []
        incomingRequests = []
        outgoingRequestIds = []
        isLoading = false
    }

    // MARK: - Loading

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let me = try await supabase.auth.session.user.id

            let rows: [Friendship] = try await supabase
                .from("friendships")
                .select()
                .or("requester_id.eq.\(me.uuidString),addressee_id.eq.\(me.uuidString)")
                .execute()
                .value

            var friendIds: [UUID] = []
            var pendingIncoming: [Friendship] = []
            var outgoing: Set<UUID> = []

            for row in rows {
                switch row.status {
                case .accepted:
                    friendIds.append(row.requesterId == me ? row.addresseeId : row.requesterId)
                case .pending:
                    if row.addresseeId == me {
                        pendingIncoming.append(row)
                    } else {
                        outgoing.insert(row.addresseeId)
                    }
                }
            }

            let profilesById = try await fetchProfiles(ids: friendIds + pendingIncoming.map { $0.requesterId })

            friends = friendIds.compactMap { profilesById[$0] }
            incomingRequests = pendingIncoming.compactMap { row in
                guard let profile = profilesById[row.requesterId] else { return nil }
                return IncomingFriendRequest(friendship: row, profile: profile)
            }
            outgoingRequestIds = outgoing
        } catch {
            print("Failed to load friends: \(error.localizedDescription)")
        }
    }

    private func fetchProfiles(ids: [UUID]) async throws -> [UUID: PublicProfile] {
        let unique = Array(Set(ids))
        guard !unique.isEmpty else { return [:] }

        let profiles: [PublicProfile] = try await supabase
            .from("profiles")
            .select("id, username, full_name, avatar_url")
            .in("id", values: unique.map { $0.uuidString })
            .execute()
            .value

        return Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
    }

    // MARK: - Mutations

    /// Sends a friend request. If the target already requested the current user, the existing request is accepted instead.
    func sendRequest(to userId: UUID) async throws {
        let me = try await supabase.auth.session.user.id
        guard userId != me else { return }

        // If they already requested us, accept that instead of creating a duplicate.
        let reverse: [Friendship] = try await supabase
            .from("friendships")
            .select()
            .eq("requester_id", value: userId)
            .eq("addressee_id", value: me)
            .execute()
            .value

        if let existing = reverse.first {
            if existing.status == .pending {
                try await accept(existing)
            }
            return
        }

        let params = CreateFriendshipParams(requesterId: me, addresseeId: userId)
        try await supabase
            .from("friendships")
            .upsert(params, onConflict: "requester_id,addressee_id")
            .execute()

        outgoingRequestIds.insert(userId)
    }

    func accept(_ friendship: Friendship) async throws {
        try await supabase
            .from("friendships")
            .update(["status": "accepted"])
            .eq("id", value: friendship.id)
            .execute()
        await refresh()
    }

    func decline(_ friendship: Friendship) async throws {
        try await supabase
            .from("friendships")
            .delete()
            .eq("id", value: friendship.id)
            .execute()
        incomingRequests.removeAll { $0.friendship.id == friendship.id }
    }

    func removeFriend(_ userId: UUID) async throws {
        let me = try await supabase.auth.session.user.id
        try await supabase
            .from("friendships")
            .delete()
            .or("and(requester_id.eq.\(me.uuidString),addressee_id.eq.\(userId.uuidString)),and(requester_id.eq.\(userId.uuidString),addressee_id.eq.\(me.uuidString))")
            .execute()
        friends.removeAll { $0.id == userId }
    }

    // MARK: - Discovery

    func searchByUsername(_ username: String) async throws -> [PublicProfile] {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let me = try await supabase.auth.session.user.id

        let profiles: [PublicProfile] = try await supabase
            .from("profiles")
            .select("id, username, full_name, avatar_url")
            .ilike("username", pattern: "%\(trimmed)%")
            .limit(20)
            .execute()
            .value

        return profiles.filter { $0.id != me }
    }

    func findFriendsByPhones(_ normalizedPhones: [String]) async throws -> [PublicProfile] {
        guard !normalizedPhones.isEmpty else { return [] }
        let profiles: [PublicProfile] = try await supabase
            .rpc("find_friends_by_phones", params: ["phones": normalizedPhones])
            .execute()
            .value
        return profiles
    }
}
