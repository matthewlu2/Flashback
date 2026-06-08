//
//  FlashbackDetailView.swift
//  Flashback
//
//  Created by Claude on 4/14/26.
//

import SwiftUI
import AVKit

struct FlashbackDetailView: View {
    let flashback: Flashback

    @State private var media: [FlashbackPhoto] = []
    @State private var isLoading = true
    @State private var mediaToDelete: FlashbackPhoto?
    @State private var showingDeleteConfirmation = false
    @State private var selectedMedia: FlashbackPhoto?
    @State private var showingShare = false
    @State private var isOwner = false

    private let columns = [
        GridItem(.flexible(), spacing: 1),
        GridItem(.flexible(), spacing: 1),
        GridItem(.flexible(), spacing: 1)
    ]

    var body: some View {
        ScrollView {
            if isLoading {
                ProgressView()
                    .padding(.top, 50)
            } else if media.isEmpty {
                Text("No photos or videos in this flashback")
                    .foregroundColor(.gray)
                    .padding(.top, 50)
            } else {
                LazyVGrid(columns: columns, spacing: 1) {
                    ForEach(media) { item in
                        MediaGridItem(media: item)
                            .aspectRatio(1, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedMedia = item
                            }
                            .contextMenu {
                                Button(role: .destructive) {
                                    mediaToDelete = item
                                    showingDeleteConfirmation = true
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
            }
        }
        .navigationTitle(flashback.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingShare = true
                } label: {
                    Image(systemName: "person.crop.circle.badge.plus")
                }
            }
        }
        .sheet(isPresented: $showingShare) {
            ShareFlashbackView(flashback: flashback, isOwner: isOwner)
        }
        .alert("Delete", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                mediaToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let item = mediaToDelete {
                    deleteMedia(item)
                }
            }
        } message: {
            Text("Are you sure you want to delete this? This cannot be undone.")
        }
        .fullScreenCover(item: $selectedMedia) { item in
            MediaFullScreenView(
                media: item,
                onDismiss: { selectedMedia = nil },
                onDelete: { media in
                    deleteMedia(media)
                    selectedMedia = nil
                }
            )
        }
        .task {
            // Resolve ownership first (it's a fast local-session check) so the share sheet
            // and owner-only controls reflect the correct state immediately.
            isOwner = await FlashbackManager.shared.isOwner(of: flashback)
            await loadMedia()
        }
    }

    private func deleteMedia(_ item: FlashbackPhoto) {
        Task {
            do {
                try await FlashbackManager.shared.deletePhoto(item)
                media.removeAll { $0.id == item.id }
            } catch {
                print("Failed to delete: \(error.localizedDescription)")
            }
            mediaToDelete = nil
        }
    }

    private func loadMedia() async {
        isLoading = true
        defer { isLoading = false }

        do {
            media = try await FlashbackManager.shared.loadPhotos(for: flashback.id)
        } catch {
            print("Failed to load media: \(error.localizedDescription)")
        }
    }
}

// MARK: - Grid Item

private struct MediaGridItem: View {
    let media: FlashbackPhoto

    var body: some View {
        ZStack {
            CachedAsyncImage(storagePath: media.thumbnailPath ?? media.storagePath, contentMode: .fill)

            if media.mediaType == .video {
                VStack {
                    Spacer()
                    HStack {
                        Image(systemName: "video.fill")
                            .font(.system(size: 12))
                        if let duration = media.durationSeconds {
                            Text(formatDuration(duration))
                                .font(.caption2)
                        }
                        Spacer()
                    }
                    .foregroundColor(.white)
                    .padding(6)
                    .background(
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.6)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
            }
        }
    }

    private func formatDuration(_ seconds: Float) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Full Screen View

struct MediaFullScreenView: View {
    let media: FlashbackPhoto
    let onDismiss: () -> Void
    let onDelete: (FlashbackPhoto) -> Void

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var showingDeleteConfirmation = false
    @State private var player: AVPlayer?
    @State private var photo: UIImage?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if media.mediaType == .video {
                VideoPlayer(player: player)
                    .task {
                        if let url = try? await FlashbackManager.shared.getSignedURL(for: media.storagePath) {
                            player = AVPlayer(url: url)
                            player?.play()
                        }
                    }
                    .onDisappear {
                        player?.pause()
                        player = nil
                    }
            } else {
                if let photo {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(scale)
                        .gesture(
                            MagnifyGesture()
                                .onChanged { value in
                                    scale = lastScale * value.magnification
                                }
                                .onEnded { _ in
                                    lastScale = scale
                                    if scale < 1.0 {
                                        withAnimation {
                                            scale = 1.0
                                            lastScale = 1.0
                                        }
                                    }
                                }
                        )
                        .onTapGesture(count: 2) {
                            withAnimation {
                                if scale > 1.0 {
                                    scale = 1.0
                                    lastScale = 1.0
                                } else {
                                    scale = 2.0
                                    lastScale = 2.0
                                }
                            }
                        }
                } else {
                    ProgressView()
                        .tint(.white)
                        .task {
                            photo = await MediaCache.shared.image(forStoragePath: media.storagePath)
                        }
                }
            }

            // Top bar
            VStack {
                HStack {
                    Button {
                        showingDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.white)
                            .padding(12)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                    .padding(.leading, 20)
                    .padding(.top, 60)

                    Spacer()

                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(.white)
                            .padding(12)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                    .padding(.trailing, 20)
                    .padding(.top, 60)
                }
                Spacer()
            }
        }
        .alert("Delete", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                onDelete(media)
            }
        } message: {
            Text("Are you sure you want to delete this? This cannot be undone.")
        }
    }
}
