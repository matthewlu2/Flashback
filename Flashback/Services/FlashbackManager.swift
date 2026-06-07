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

    func loadFlashbacksIfNeeded() async {
        guard !hasLoadedFlashbacks else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let userId = try await supabase.auth.session.user.id

            let response: [Flashback] = try await supabase
                .from("flashbacks")
                .select()
                .eq("user_id", value: userId)
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
}
