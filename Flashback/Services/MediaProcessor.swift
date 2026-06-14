//
//  MediaProcessor.swift
//  Flashback
//
//  Utilities for downscaling images, generating thumbnails and video
//  poster frames, and compressing videos before upload.
//

import UIKit
import AVFoundation

enum MediaProcessor {

    // MARK: - Images

    /// Returns a copy of the image scaled so its largest side is at most `maxDimension`.
    /// Images already smaller than the limit are returned unchanged.
    static func downscaleImage(_ image: UIImage, maxDimension: CGFloat = 2048) -> UIImage {
        let largestSide = max(image.size.width, image.size.height)
        guard largestSide > maxDimension else { return image }

        let scale = maxDimension / largestSide
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    /// Generates small JPEG thumbnail data (largest side <= `maxDimension`).
    static func thumbnailData(from image: UIImage, maxDimension: CGFloat = 400, quality: CGFloat = 0.6) -> Data? {
        let thumb = downscaleImage(image, maxDimension: maxDimension)
        return thumb.jpegData(compressionQuality: quality)
    }

    /// Renders the portion of `image` visible inside a circular crop, exported as a square bitmap.
    static func croppedSquareImage(
        from image: UIImage,
        scale: CGFloat,
        offset: CGSize,
        cropDiameter: CGFloat,
        outputMaxDimension: CGFloat = 512
    ) -> UIImage? {
        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0 else { return nil }

        let baseScale = max(cropDiameter / imageSize.width, cropDiameter / imageSize.height)
        let totalScale = baseScale * scale
        let drawWidth = imageSize.width * totalScale
        let drawHeight = imageSize.height * totalScale
        let outputScale = outputMaxDimension / cropDiameter

        let outputSize = CGSize(width: outputMaxDimension, height: outputMaxDimension)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: outputSize, format: format)

        return renderer.image { context in
            let cgContext = context.cgContext
            cgContext.addEllipse(in: CGRect(origin: .zero, size: outputSize))
            cgContext.clip()

            let origin = CGPoint(
                x: (outputSize.width - drawWidth * outputScale) / 2 + offset.width * outputScale,
                y: (outputSize.height - drawHeight * outputScale) / 2 + offset.height * outputScale
            )
            image.draw(in: CGRect(
                x: origin.x,
                y: origin.y,
                width: drawWidth * outputScale,
                height: drawHeight * outputScale
            ))
        }
    }

    // MARK: - Video

    /// Extracts a poster frame from the start of a video.
    static func posterFrame(forVideo url: URL) async -> UIImage? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let asset = AVURLAsset(url: url)
                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                generator.maximumSize = CGSize(width: 800, height: 800)

                do {
                    let cgImage = try generator.copyCGImage(at: .zero, actualTime: nil)
                    continuation.resume(returning: UIImage(cgImage: cgImage))
                } catch {
                    print("Failed to generate poster frame: \(error.localizedDescription)")
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    /// Compresses a video to a smaller 720p-class MP4. Returns the original URL on failure.
    static func compressVideo(_ inputURL: URL) async -> URL {
        let asset = AVURLAsset(url: inputURL)

        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset1280x720) else {
            return inputURL
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true

        await exportSession.export()

        if exportSession.status == .completed {
            return outputURL
        } else {
            if let error = exportSession.error {
                print("Video compression failed: \(error.localizedDescription)")
            }
            return inputURL
        }
    }
}
