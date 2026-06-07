//
//  FlashbackPickerView.swift
//  Flashback
//
//  Created by Claude on 4/14/26.
//

import SwiftUI

struct FlashbackPickerView: View {
    @Binding var selectedFlashback: Flashback?
    @Binding var showingCreateNew: Bool
    @StateObject private var flashbackManager = FlashbackManager.shared
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            List {
                Button {
                    dismiss()
                    showingCreateNew = true
                } label: {
                    Label("Create New Flashback", systemImage: "plus.circle.fill")
                        .foregroundColor(.blue)
                }

                if flashbackManager.flashbacks.isEmpty && !flashbackManager.isLoading {
                    Text("No flashbacks yet")
                        .foregroundColor(.gray)
                } else {
                    ForEach(flashbackManager.flashbacks) { flashback in
                        FlashbackRowView(flashback: flashback, isSelected: selectedFlashback?.id == flashback.id)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedFlashback = flashback
                                dismiss()
                            }
                    }
                }
            }
            .navigationTitle("Choose Flashback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .task {
            await flashbackManager.loadFlashbacksIfNeeded()
        }
    }
}

struct FlashbackRowView: View {
    let flashback: Flashback
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Cover image thumbnail
            Group {
                if let coverPath = flashback.coverThumbnailPath ?? flashback.coverImagePath {
                    CachedAsyncImage(storagePath: coverPath, contentMode: .fill)
                } else {
                    // No photos - show default album icon
                    Color.gray.opacity(0.2)
                        .overlay {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.system(size: 16))
                                .foregroundColor(.gray)
                        }
                }
            }
            .frame(width: 50, height: 50)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(flashback.name)
                .font(.body)

            Spacer()

            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundColor(.blue)
            }
        }
    }
}
