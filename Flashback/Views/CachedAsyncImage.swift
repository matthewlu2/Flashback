//
//  CachedAsyncImage.swift
//  Flashback
//
//  Drop-in replacement for AsyncImage that loads through MediaCache,
//  keyed by Supabase storage path instead of a (rotating) signed URL.
//

import SwiftUI

struct CachedAsyncImage: View {
    let storagePath: String?
    var contentMode: ContentMode = .fill

    @State private var image: UIImage?
    @State private var didFail = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                Color.gray.opacity(0.3)
                    .overlay {
                        if !didFail {
                            ProgressView()
                                .tint(.white)
                        }
                    }
            }
        }
        .task(id: storagePath) {
            await load()
        }
    }

    private func load() async {
        image = nil
        didFail = false

        guard let storagePath, !storagePath.isEmpty else {
            didFail = true
            return
        }

        let loaded = await MediaCache.shared.image(forStoragePath: storagePath)
        if let loaded {
            image = loaded
        } else {
            didFail = true
        }
    }
}
