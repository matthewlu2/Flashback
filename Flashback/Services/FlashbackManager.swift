//
//  FlashbackManager.swift
//  Flashback
//
//  Created by Claude on 4/14/26.
//

import SwiftUI
import Supabase
import Combine

@MainActor
class FlashbackManager: ObservableObject {
    static let shared = FlashbackManager()

    @Published var flashbacks: [Flashback] = []
    @Published var isLoading = false
    @Published var hasLoadedFlashbacks = false

    private init() {}

    /// Clears all cached state. Call when the authenticated user changes so one account's
    /// albums never leak into (or hide) another's.
    func reset() {
        flashbacks = []
        hasLoadedFlashbacks = false
        isLoading = false
    }

    func loadFlashbacksIfNeeded() async {
        guard !hasLoadedFlashbacks else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            // RLS returns every flashback the current user is a member of (owner or invited).
            let response: [Flashback] = try await supabase
                .from("flashbacks")
                .select()
                .order("created_at", ascending: false)
                .execute()
                .value

            flashbacks = response
            hasLoadedFlashbacks = true
        } catch {
            print("Failed to load flashbacks: \(error.localizedDescription)")
        }
    }

    func createFlashback(name: String) async throws -> Flashback {
        let userId = try await supabase.auth.session.user.id

        let params = CreateFlashbackParams(userId: userId, name: name)

        let flashback: Flashback = try await supabase
            .from("flashbacks")
            .insert(params)
            .select()
            .single()
            .execute()
            .value

        flashbacks.insert(flashback, at: 0)
        return flashback
    }

    func loadPhotos(for flashbackId: UUID) async throws -> [FlashbackPhoto] {
        let response: [FlashbackPhoto] = try await supabase
            .from("flashback_photos")
            .select()
            .eq("flashback_id", value: flashbackId)
            .order("created_at", ascending: false)
            .execute()
            .value

        return response
    }

    func addMedia(storagePath: String, thumbnailPath: String? = nil, mediaType: MediaType, duration: Float? = nil, toFlashback flashbackId: UUID) async throws {
        let params = CreateFlashbackPhotoParams(
            flashbackId: flashbackId,
            storagePath: storagePath,
            thumbnailPath: thumbnailPath,
            mediaType: mediaType,
            durationSeconds: duration
        )

        try await supabase
            .from("flashback_photos")
            .insert(params)
            .execute()

        // Update cover image if not set
        if let index = flashbacks.firstIndex(where: { $0.id == flashbackId }),
           flashbacks[index].coverImagePath == nil {
            try await supabase
                .from("flashbacks")
                .update([
                    "cover_image_path": storagePath,
                    "cover_thumbnail_path": thumbnailPath
                ])
                .eq("id", value: flashbackId)
                .execute()

            // Reload to get updated flashback
            hasLoadedFlashbacks = false
            await loadFlashbacksIfNeeded()
        }
    }

    func getSignedURL(for storagePath: String) async throws -> URL {
        return try await supabase.storage
            .from("images")
            .createSignedURL(path: storagePath, expiresIn: 3600)
    }

    func refresh() {
        hasLoadedFlashbacks = false
        Task {
            await loadFlashbacksIfNeeded()
        }
    }

    func deletePhoto(_ photo: FlashbackPhoto) async throws {
        // Delete from storage (original + thumbnail)
        var pathsToRemove = [photo.storagePath]
        if let thumbnailPath = photo.thumbnailPath {
            pathsToRemove.append(thumbnailPath)
        }
        try await supabase.storage
            .from("images")
            .remove(paths: pathsToRemove)

        // Clear cache entries
        await MediaCache.shared.remove(storagePath: photo.storagePath)
        if let thumbnailPath = photo.thumbnailPath {
            await MediaCache.shared.remove(storagePath: thumbnailPath)
        }

        // Delete from database
        try await supabase
            .from("flashback_photos")
            .delete()
            .eq("id", value: photo.id)
            .execute()
    }

    func getFirstPhotoURL(for flashbackId: UUID) async -> URL? {
        do {
            let photos: [FlashbackPhoto] = try await supabase
                .from("flashback_photos")
                .select()
                .eq("flashback_id", value: flashbackId)
                .order("created_at", ascending: true)
                .limit(1)
                .execute()
                .value

            guard let firstPhoto = photos.first else { return nil }
            return try await getSignedURL(for: firstPhoto.storagePath)
        } catch {
            print("Failed to get first photo: \(error.localizedDescription)")
            return nil
        }
    }

    func isFlashbackEmpty(_ flashbackId: UUID) async -> Bool {
        do {
            let photos: [FlashbackPhoto] = try await supabase
                .from("flashback_photos")
                .select()
                .eq("flashback_id", value: flashbackId)
                .limit(1)
                .execute()
                .value

            return photos.isEmpty
        } catch {
            print("Failed to check if flashback is empty: \(error.localizedDescription)")
            return false
        }
    }

    func deleteFlashback(_ flashback: Flashback) async throws {
        // Delete from database (cascade will handle flashback_photos if any)
        try await supabase
            .from("flashbacks")
            .delete()
            .eq("id", value: flashback.id)
            .execute()

        // Remove from local array
        flashbacks.removeAll { $0.id == flashback.id }
    }

    // MARK: - Membership & sharing

    func currentUserId() async -> UUID? {
        try? await supabase.auth.session.user.id
    }

    /// True when the given flashback was created by (and is owned by) the current user.
    func isOwner(of flashback: Flashback) async -> Bool {
        guard let me = await currentUserId() else { return false }
        return flashback.userId == me
    }

    func members(for flashbackId: UUID) async throws -> [MemberInfo] {
        let rows: [FlashbackMember] = try await supabase
            .from("flashback_members")
            .select()
            .eq("flashback_id", value: flashbackId)
            .order("created_at", ascending: true)
            .execute()
            .value

        let profiles = try await fetchProfiles(ids: rows.map { $0.userId })
        return rows.map { row in
            MemberInfo(
                userId: row.userId,
                role: row.role,
                profile: profiles[row.userId]
            )
        }
    }

    func pendingRequests(for flashbackId: UUID) async throws -> [JoinRequestInfo] {
        let rows: [FlashbackJoinRequest] = try await supabase
            .from("flashback_join_requests")
            .select()
            .eq("flashback_id", value: flashbackId)
            .eq("status", value: "pending")
            .order("created_at", ascending: true)
            .execute()
            .value

        let profiles = try await fetchProfiles(ids: rows.map { $0.userId })
        return rows.map { row in
            JoinRequestInfo(request: row, profile: profiles[row.userId])
        }
    }

    func approve(requestId: UUID) async throws {
        try await supabase
            .rpc("approve_join_request", params: ["request_id": requestId])
            .execute()
    }

    func deny(requestId: UUID) async throws {
        try await supabase
            .rpc("deny_join_request", params: ["request_id": requestId])
            .execute()
    }

    /// Owner directly adds a friend (in-app invite = pre-approved).
    func addMember(_ userId: UUID, to flashbackId: UUID) async throws {
        try await supabase
            .rpc("add_member", params: ["p_flashback_id": flashbackId.uuidString, "p_user_id": userId.uuidString])
            .execute()
    }

    func leave(flashbackId: UUID) async throws {
        guard let me = await currentUserId() else { return }
        try await supabase
            .from("flashback_members")
            .delete()
            .eq("flashback_id", value: flashbackId)
            .eq("user_id", value: me)
            .execute()
        flashbacks.removeAll { $0.id == flashbackId }
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
}

struct MemberInfo: Identifiable {
    let userId: UUID
    let role: MemberRole
    let profile: PublicProfile?
    var id: UUID { userId }
    var displayName: String { profile?.displayName ?? "Member" }
}

struct JoinRequestInfo: Identifiable {
    let request: FlashbackJoinRequest
    let profile: PublicProfile?
    var id: UUID { request.id }
    var displayName: String { profile?.displayName ?? "Someone" }
}
