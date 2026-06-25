//
//  UploadManager.swift
//  Flashback
//
//  Created by Matthew Lu on 4/7/26.
//

import SwiftUI
import Supabase
import Combine
import AVFoundation

enum MediaItem: Identifiable {
    case localImage(UIImage)
    case localVideo(URL)
    case remote(URL, MediaType)

    var id: String {
        switch self {
        case .localImage(let image):
            return "\(ObjectIdentifier(image))"
        case .localVideo(let url):
            return url.absoluteString
        case .remote(let url, _):
            return url.absoluteString
        }
    }
}

@MainActor
class UploadManager: ObservableObject {
    static let shared = UploadManager()

    @Published var isUploading = false
    @Published var pendingUploads = 0
    @Published var hasLoadedPhotos = false

    private init() {}

    func uploadPhoto(_ image: UIImage, takenAt: Date = Date(), toFlashback flashbackId: UUID) {
        let downscaled = MediaProcessor.downscaleImage(image, maxDimension: 2048)
        guard let imageData = downscaled.jpegData(compressionQuality: 0.8) else {
            print("Failed to process image for upload")
            return
        }
        let thumbnailData = MediaProcessor.thumbnailData(from: image)

        pendingUploads += 1
        isUploading = true

        Task {
            defer {
                pendingUploads -= 1
                if pendingUploads == 0 {
                    isUploading = false
                }
            }

            do {
                // Lowercase to match storage RLS, which compares the folder segment against
                // auth.uid()::text (always lowercase). Swift's uuidString is uppercase.
                let userId = try await supabase.auth.session.user.id.uuidString.lowercased()
                let assetId = UUID().uuidString.lowercased()
                let storagePath = "\(userId)/\(assetId).jpg"
                var thumbnailPath: String?

                try await supabase.storage
                    .from("images")
                    .upload(storagePath, data: imageData, options: .init(contentType: "image/jpeg"))

                if let thumbnailData {
                    let path = "\(userId)/thumb_\(assetId).jpg"
                    try await supabase.storage
                        .from("images")
                        .upload(path, data: thumbnailData, options: .init(contentType: "image/jpeg"))
                    thumbnailPath = path
                }

                try await FlashbackManager.shared.addMedia(
                    storagePath: storagePath,
                    thumbnailPath: thumbnailPath,
                    mediaType: .photo,
                    takenAt: takenAt,
                    toFlashback: flashbackId
                )

                print("Photo uploaded successfully: \(storagePath)")
            } catch {
                print("Upload failed: \(error.localizedDescription)")
            }
        }
    }

    func uploadVideo(_ videoURL: URL, toFlashback flashbackId: UUID) {
        pendingUploads += 1
        isUploading = true

        Task {
            defer {
                pendingUploads -= 1
                if pendingUploads == 0 {
                    isUploading = false
                }
            }

            do {
                // Poster frame from the original (before compression) for the thumbnail.
                let posterFrame = await MediaProcessor.posterFrame(forVideo: videoURL)
                let thumbnailData = posterFrame.flatMap { MediaProcessor.thumbnailData(from: $0) }

                // Prefer the original clip's recorded creation date as the "taken" time.
                let takenAt = await getVideoCreationDate(url: videoURL) ?? Date()

                let compressedURL = await MediaProcessor.compressVideo(videoURL)
                let videoData = try Data(contentsOf: compressedURL)
                let duration = await getVideoDuration(url: compressedURL)

                // Lowercase to match storage RLS, which compares the folder segment against
                // auth.uid()::text (always lowercase). Swift's uuidString is uppercase.
                let userId = try await supabase.auth.session.user.id.uuidString.lowercased()
                let assetId = UUID().uuidString.lowercased()
                let storagePath = "\(userId)/\(assetId).mp4"
                var thumbnailPath: String?

                try await supabase.storage
                    .from("images")
                    .upload(storagePath, data: videoData, options: .init(contentType: "video/mp4"))

                if let thumbnailData {
                    let path = "\(userId)/thumb_\(assetId).jpg"
                    try await supabase.storage
                        .from("images")
                        .upload(path, data: thumbnailData, options: .init(contentType: "image/jpeg"))
                    thumbnailPath = path
                }

                try await FlashbackManager.shared.addMedia(
                    storagePath: storagePath,
                    thumbnailPath: thumbnailPath,
                    mediaType: .video,
                    duration: duration,
                    takenAt: takenAt,
                    toFlashback: flashbackId
                )

                print("Video uploaded successfully: \(storagePath)")

                // Clean up temp files
                try? FileManager.default.removeItem(at: videoURL)
                if compressedURL != videoURL {
                    try? FileManager.default.removeItem(at: compressedURL)
                }
            } catch {
                print("Video upload failed: \(error.localizedDescription)")
            }
        }
    }

    private func getVideoDuration(url: URL) async -> Float? {
        let asset = AVURLAsset(url: url)
        do {
            let duration = try await asset.load(.duration)
            return Float(CMTimeGetSeconds(duration))
        } catch {
            return nil
        }
    }

    /// Reads the recorded creation date from a video asset's metadata, if present.
    private func getVideoCreationDate(url: URL) async -> Date? {
        let asset = AVURLAsset(url: url)
        guard let item = try? await asset.load(.creationDate) else { return nil }
        return try? await item.load(.dateValue)
    }
}
