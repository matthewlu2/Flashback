//
//  PhotoLibrarySaver.swift
//  Flashback
//
//  Saves album photos and videos to the user's local camera roll using the
//  Photos framework. Reuses MediaCache for photo bytes and FlashbackManager's
//  signed URLs for video downloads.
//

import Photos
import UIKit

enum PhotoLibrarySaver {
    enum SaveError: LocalizedError {
        case permissionDenied
        case mediaUnavailable

        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                return "Flashback needs permission to add to your photo library. Enable it in Settings."
            case .mediaUnavailable:
                return "This item couldn't be loaded to save."
            }
        }
    }

    /// Requests add-only access to the photo library if needed.
    static func ensureAuthorized() async -> Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        switch status {
        case .authorized, .limited:
            return true
        case .notDetermined:
            let updated = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            return updated == .authorized || updated == .limited
        default:
            return false
        }
    }

    /// Saves a single photo or video to the camera roll.
    static func save(_ media: FlashbackPhoto) async throws {
        guard await ensureAuthorized() else { throw SaveError.permissionDenied }

        switch media.mediaType {
        case .photo:
            guard let image = await MediaCache.shared.image(forStoragePath: media.storagePath) else {
                throw SaveError.mediaUnavailable
            }
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }
        case .video:
            let url = try await FlashbackManager.shared.getSignedURL(for: media.storagePath)
            let (data, _) = try await URLSession.shared.data(from: url)
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(media.id.uuidString).mp4")
            try data.write(to: tempURL, options: .atomic)
            defer { try? FileManager.default.removeItem(at: tempURL) }
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: tempURL)
            }
        }
    }

    /// Saves multiple items, returning how many succeeded and failed.
    static func saveAll(_ items: [FlashbackPhoto]) async -> (saved: Int, failed: Int) {
        var saved = 0
        var failed = 0
        for item in items {
            do {
                try await save(item)
                saved += 1
            } catch {
                failed += 1
            }
        }
        return (saved, failed)
    }
}
