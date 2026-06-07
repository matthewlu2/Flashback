//
//  MediaPreviewView.swift
//  Flashback
//
//  Created by Matthew Lu on 6/7/26.
//

import SwiftUI
import AVKit

enum CapturedMedia {
    case photo(UIImage)
    case video(URL)
}

struct MediaPreviewView: View {
    let media: CapturedMedia
    let selectedFlashback: Flashback?
    let onDismiss: () -> Void

    @StateObject private var flashbackManager = FlashbackManager.shared
    @State private var localSelectedFlashback: Flashback?
    @State private var showingFlashbackPicker = false
    @State private var showingCreateFlashback = false
    @State private var player: AVPlayer?

    private static let lastFlashbackKey = "lastSelectedFlashbackId"

    var body: some View {
        VStack {
            // Top bar with Retake button
            HStack {
                Button("Retake") {
                    cleanupAndDismiss()
                }
                .padding()

                Spacer()
            }
            .background(.ultraThinMaterial)

            // Media preview
            switch media {
            case .photo(let image):
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()

            case .video(let url):
                VideoPlayerView(url: url)
            }

            Spacer()

            // Bottom section: Flashback selection
            VStack(spacing: 16) {
                // Flashback selector button
                Button {
                    showingFlashbackPicker = true
                } label: {
                    HStack {
                        Image(systemName: "rectangle.stack")
                        Text(currentFlashback?.name ?? "Choose Flashback")
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                }
                .foregroundColor(currentFlashback != nil ? .primary : .secondary)

                // Send button
                Button {
                    sendToFlashback()
                } label: {
                    HStack {
                        Image(systemName: isVideo ? "video.fill" : "photo.fill")
                        Text(isVideo ? "Send Video to Flashback" : "Send to Flashback")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(currentFlashback != nil ? Color.blue : Color.gray)
                    .cornerRadius(10)
                }
                .disabled(currentFlashback == nil)
            }
            .padding()
        }
        .sheet(isPresented: $showingFlashbackPicker) {
            FlashbackPickerView(
                selectedFlashback: $localSelectedFlashback,
                showingCreateNew: $showingCreateFlashback
            )
        }
        .sheet(isPresented: $showingCreateFlashback) {
            CreateFlashbackView { flashback in
                localSelectedFlashback = flashback
                UserDefaults.standard.set(flashback.id.uuidString, forKey: Self.lastFlashbackKey)
            }
        }
        .task {
            await flashbackManager.loadFlashbacksIfNeeded()
            // Use passed-in selection or fall back to last used
            if let selected = selectedFlashback {
                localSelectedFlashback = selected
            } else if let lastIdString = UserDefaults.standard.string(forKey: Self.lastFlashbackKey),
                      let lastId = UUID(uuidString: lastIdString) {
                localSelectedFlashback = flashbackManager.flashbacks.first { $0.id == lastId }
            }
        }
    }

    private var currentFlashback: Flashback? {
        localSelectedFlashback ?? selectedFlashback
    }

    private var isVideo: Bool {
        if case .video = media { return true }
        return false
    }

    private func sendToFlashback() {
        guard let flashback = currentFlashback else { return }

        UserDefaults.standard.set(flashback.id.uuidString, forKey: Self.lastFlashbackKey)

        switch media {
        case .photo(let image):
            UploadManager.shared.uploadPhoto(image, toFlashback: flashback.id)
        case .video(let url):
            UploadManager.shared.uploadVideo(url, toFlashback: flashback.id)
        }

        onDismiss()
    }

    private func cleanupAndDismiss() {
        if case .video(let url) = media {
            try? FileManager.default.removeItem(at: url)
        }
        onDismiss()
    }
}

// MARK: - Video Player

private struct VideoPlayerView: View {
    let url: URL
    @State private var player: AVPlayer?

    var body: some View {
        VideoPlayer(player: player)
            .onAppear {
                player = AVPlayer(url: url)
                player?.play()
            }
            .onDisappear {
                player?.pause()
                player = nil
            }
    }
}
