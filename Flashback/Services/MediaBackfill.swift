//
//  MediaBackfill.swift
//  Flashback
//
//  One-time sweep that generates and uploads thumbnails for media that was
//  uploaded before thumbnail support existed, and backfills cover thumbnails.
//

import UIKit
import Supabase

enum MediaBackfill {
    private static let completedKey = "mediaThumbnailBackfillComplete"

    /// Runs the backfill once. Safe to call on every launch; it no-ops after success.
    static func runIfNeeded() async {
        guard !UserDefaults.standard.bool(forKey: completedKey) else { return }

        do {
            let userId = try await supabase.auth.session.user.id

            let flashbacks: [Flashback] = try await supabase
                .from("flashbacks")
                .select()
                .eq("user_id", value: userId)
                .execute()
                .value

            for flashback in flashbacks {
                let photos: [FlashbackPhoto] = try await supabase
                    .from("flashback_photos")
                    .select()
                    .eq("flashback_id", value: flashback.id)
                    .execute()
                    .value

                var thumbnailByStoragePath: [String: String] = [:]

                for photo in photos {
                    if let existing = photo.thumbnailPath {
                        thumbnailByStoragePath[photo.storagePath] = existing
                        continue
                    }

                    if let thumbnailPath = await generateThumbnail(for: photo, userId: userId) {
                        try? await supabase
                            .from("flashback_photos")
                            .update(["thumbnail_path": thumbnailPath])
                            .eq("id", value: photo.id)
                            .execute()

                        thumbnailByStoragePath[photo.storagePath] = thumbnailPath
                    }
                }

                // Backfill the cover thumbnail from the cover photo's thumbnail.
                if flashback.coverThumbnailPath == nil,
                   let coverPath = flashback.coverImagePath,
                   let coverThumb = thumbnailByStoragePath[coverPath] {
                    try? await supabase
                        .from("flashbacks")
                        .update(["cover_thumbnail_path": coverThumb])
                        .eq("id", value: flashback.id)
                        .execute()
                }
            }

            UserDefaults.standard.set(true, forKey: completedKey)
            print("Media thumbnail backfill complete")
        } catch {
            print("Media backfill failed (will retry next launch): \(error.localizedDescription)")
        }
    }

    /// Downloads the original, builds a thumbnail, uploads it, and returns its storage path.
    private static func generateThumbnail(for photo: FlashbackPhoto, userId: UUID) async -> String? {
        guard let signedURL = try? await supabase.storage
            .from("images")
            .createSignedURL(path: photo.storagePath, expiresIn: 3600) else {
            return nil
        }

        guard let (data, _) = try? await URLSession.shared.data(from: signedURL) else {
            return nil
        }

        var thumbnailData: Data?

        switch photo.mediaType {
        case .photo:
            if let image = UIImage(data: data) {
                thumbnailData = MediaProcessor.thumbnailData(from: image)
            }
        case .video:
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("mp4")
            try? data.write(to: tempURL, options: .atomic)
            if let poster = await MediaProcessor.posterFrame(forVideo: tempURL) {
                thumbnailData = MediaProcessor.thumbnailData(from: poster)
            }
            try? FileManager.default.removeItem(at: tempURL)
        }

        guard let thumbnailData else { return nil }

        let thumbnailPath = "\(userId)/thumb_\(UUID().uuidString).jpg"
        do {
            try await supabase.storage
                .from("images")
                .upload(thumbnailPath, data: thumbnailData, options: .init(contentType: "image/jpeg"))
            return thumbnailPath
        } catch {
            print("Failed to upload backfill thumbnail: \(error.localizedDescription)")
            return nil
        }
    }
}
