//
//  MediaCache.swift
//  Flashback
//
//  Lightweight image cache keyed by Supabase storage path. Combines an
//  in-memory NSCache with an on-disk cache so images are only downloaded
//  once. Signed URLs are cached briefly to avoid repeated createSignedURL
//  round-trips.
//

import UIKit
import Supabase

actor MediaCache {
    static let shared = MediaCache()

    private let memoryCache = NSCache<NSString, UIImage>()
    private let fileManager = FileManager.default
    private let diskDirectory: URL

    // Cached signed URLs with their expiry (refresh well before the 1h limit).
    private var signedURLs: [String: (url: URL, expires: Date)] = [:]
    private let signedURLLifetime: TimeInterval = 3000 // 50 minutes

    // Coalesce concurrent requests for the same path.
    private var inFlight: [String: Task<UIImage?, Never>] = [:]

    init() {
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        diskDirectory = caches.appendingPathComponent("media", isDirectory: true)
        try? fileManager.createDirectory(at: diskDirectory, withIntermediateDirectories: true)
    }

    /// Returns the image for a storage path, loading from memory, disk, or network as needed.
    func image(forStoragePath storagePath: String) async -> UIImage? {
        let key = Self.sanitize(storagePath)

        if let cached = memoryCache.object(forKey: key as NSString) {
            return cached
        }

        if let existing = inFlight[key] {
            return await existing.value
        }

        let task = Task<UIImage?, Never> {
            // Disk
            let fileURL = diskDirectory.appendingPathComponent(key)
            if let data = try? Data(contentsOf: fileURL), let image = UIImage(data: data) {
                memoryCache.setObject(image, forKey: key as NSString)
                return image
            }

            // Network
            guard let signedURL = await signedURL(for: storagePath) else { return nil }
            guard let (data, _) = try? await URLSession.shared.data(from: signedURL),
                  let image = UIImage(data: data) else {
                return nil
            }

            try? data.write(to: fileURL, options: .atomic)
            memoryCache.setObject(image, forKey: key as NSString)
            return image
        }

        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        return result
    }

    /// Removes a cached image (memory + disk) for a storage path.
    func remove(storagePath: String) {
        let key = Self.sanitize(storagePath)
        memoryCache.removeObject(forKey: key as NSString)
        let fileURL = diskDirectory.appendingPathComponent(key)
        try? fileManager.removeItem(at: fileURL)
        signedURLs[storagePath] = nil
    }

    private func signedURL(for storagePath: String) async -> URL? {
        if let entry = signedURLs[storagePath], entry.expires > Date() {
            return entry.url
        }

        do {
            let url = try await supabase.storage
                .from("images")
                .createSignedURL(path: storagePath, expiresIn: 3600)
            signedURLs[storagePath] = (url, Date().addingTimeInterval(signedURLLifetime))
            return url
        } catch {
            print("Failed to create signed URL: \(error.localizedDescription)")
            return nil
        }
    }

    private static func sanitize(_ path: String) -> String {
        path.replacingOccurrences(of: "/", with: "_")
    }
}
