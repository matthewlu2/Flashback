//
//  ProfileView.swift
//  Flashback
//
//  Created by Matthew Lu on 1/28/26.
//

import Foundation
import SwiftUI
import Supabase

struct ProfileView: View {
  @StateObject private var flashbackManager = FlashbackManager.shared
  @StateObject private var friendsManager = FriendsManager.shared
  @State private var profile: Profile?
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
        VStack(alignment: .leading, spacing: 0) {
          ProfileHeaderView(
            profile: profile,
            friendsCount: friendsManager.friends.count,
            flashbacksCount: flashbackManager.flashbacks.count
          )
          .padding(.horizontal)
          .padding(.top)

          Divider()
            .padding(.horizontal)
            .padding(.vertical, 12)

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
      }
      .navigationTitle("")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            showingSettings = true
          } label: {
            Image(systemName: "gearshape")
          }
        }
      }
      .sheet(isPresented: $showingSettings, onDismiss: {
        Task { await loadProfile() }
      }) {
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
      async let flashbacks: Void = flashbackManager.loadFlashbacksIfNeeded()
      async let friends: Void = friendsManager.refresh()
      async let profileLoad: Void = loadProfile()
      _ = await (flashbacks, friends, profileLoad)
    }
  }

  private func loadProfile() async {
    do {
      let currentUser = try await supabase.auth.session.user
      let loaded: Profile = try await supabase
        .from("profiles")
        .select()
        .eq("id", value: currentUser.id)
        .single()
        .execute()
        .value
      profile = loaded
    } catch {
      debugPrint(error)
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

private struct ProfileHeaderView: View {
  let profile: Profile?
  let friendsCount: Int
  let flashbacksCount: Int

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .center, spacing: 24) {
        AvatarView(
          urlPath: profile?.avatarUrl,
          name: profile?.displayName ?? "Unknown",
          size: 86
        )

        HStack(spacing: 20) {
          ProfileStatView(count: flashbacksCount, label: "Flashbacks")
          NavigationLink {
            FriendsView()
          } label: {
            ProfileStatView(count: friendsCount, label: "Friends")
          }
          .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
      }

      if let username = profile?.username, !username.isEmpty {
        Text("@\(username)")
          .font(.subheadline.weight(.semibold))
      }

      if let fullName = profile?.fullName,
         !fullName.isEmpty,
         fullName != profile?.username {
        Text(fullName)
          .font(.subheadline)
          .foregroundColor(.gray)
      }
    }
  }
}

private struct ProfileStatView: View {
  let count: Int
  let label: String

  var body: some View {
    VStack(spacing: 2) {
      Text("\(count)")
        .font(.headline.weight(.semibold))
      Text(label)
        .font(.caption)
        .foregroundColor(.gray)
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
