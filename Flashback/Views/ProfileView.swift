//
//  ProfileView.swift
//  Flashback
//
//  Created by Matthew Lu on 1/28/26.
//

import Foundation
import SwiftUI

struct ProfileView: View {
  @StateObject private var flashbackManager = FlashbackManager.shared
  @State private var showingSettings = false
  @State private var flashbackToDelete: Flashback?
  @State private var showingDeleteAlert = false
  @State private var deleteError: String?

  private let columns = [
    GridItem(.flexible()),
    GridItem(.flexible()),
    GridItem(.flexible())
  ]

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading) {
          Text("My Flashbacks")
            .font(.headline)
            .padding(.horizontal)

          if flashbackManager.flashbacks.isEmpty && !flashbackManager.isLoading {
            Text("No flashbacks yet")
              .foregroundColor(.gray)
              .padding()
          } else {
            LazyVGrid(columns: columns, spacing: 2) {
              ForEach(flashbackManager.flashbacks) { flashback in
                NavigationLink(destination: FlashbackDetailView(flashback: flashback)) {
                  FlashbackGridItemView(flashback: flashback)
                }
                .contextMenu {
                  Button(role: .destructive) {
                    flashbackToDelete = flashback
                    checkAndDeleteFlashback(flashback)
                  } label: {
                    Label("Delete", systemImage: "trash")
                  }
                }
              }
            }
          }
        }
        .padding(.top)
      }
      .navigationTitle("Profile")
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          NavigationLink {
            FriendsView()
          } label: {
            Image(systemName: "person.2")
          }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            showingSettings = true
          } label: {
            Image(systemName: "gearshape")
          }
        }
      }
      .sheet(isPresented: $showingSettings) {
        SettingsView()
      }
      .alert("Delete Flashback", isPresented: $showingDeleteAlert) {
        Button("Cancel", role: .cancel) {
          flashbackToDelete = nil
        }
        Button("Delete", role: .destructive) {
          if let flashback = flashbackToDelete {
            deleteFlashback(flashback)
          }
        }
      } message: {
        Text("Are you sure you want to delete \"\(flashbackToDelete?.name ?? "")\"?")
      }
      .alert("Cannot Delete", isPresented: .init(
        get: { deleteError != nil },
        set: { if !$0 { deleteError = nil } }
      )) {
        Button("OK", role: .cancel) {}
      } message: {
        Text(deleteError ?? "")
      }
    }
    .task {
      await flashbackManager.loadFlashbacksIfNeeded()
    }
  }

  private func checkAndDeleteFlashback(_ flashback: Flashback) {
    Task {
      let isEmpty = await FlashbackManager.shared.isFlashbackEmpty(flashback.id)
      if isEmpty {
        showingDeleteAlert = true
      } else {
        deleteError = "This flashback contains photos. Delete all photos first before deleting the flashback."
      }
    }
  }

  private func deleteFlashback(_ flashback: Flashback) {
    Task {
      do {
        try await FlashbackManager.shared.deleteFlashback(flashback)
      } catch {
        deleteError = "Failed to delete flashback: \(error.localizedDescription)"
      }
      flashbackToDelete = nil
    }
  }
}

struct FlashbackGridItemView: View {
  let flashback: Flashback

  var body: some View {
    GeometryReader { geometry in
      ZStack(alignment: .bottom) {
        // Cover image or default
        Group {
          if let coverPath = flashback.coverThumbnailPath ?? flashback.coverImagePath {
            CachedAsyncImage(storagePath: coverPath, contentMode: .fill)
          } else {
            // No photos - show default album icon
            Color.gray.opacity(0.2)
              .overlay {
                Image(systemName: "photo.on.rectangle.angled")
                  .font(.system(size: 30))
                  .foregroundColor(.gray)
              }
          }
        }
        .frame(width: geometry.size.width, height: geometry.size.width)

        // Name overlay
        Text(flashback.name)
          .font(.caption)
          .fontWeight(.semibold)
          .foregroundColor(.white)
          .shadow(color: .black.opacity(0.7), radius: 2, x: 0, y: 1)
          .padding(.horizontal, 6)
          .padding(.bottom, 6)
      }
      .frame(width: geometry.size.width, height: geometry.size.width)
      .clipped()
      .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    .aspectRatio(1, contentMode: .fit)
  }
}

#Preview {
    ProfileView()
}
