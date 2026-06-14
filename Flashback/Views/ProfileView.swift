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
    GridItem(.flexible(), spacing: 12),
    GridItem(.flexible(), spacing: 12),
    GridItem(.flexible(), spacing: 12)
  ]

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          ProfileHeaderView(
            profile: profile,
            friendsCount: friendsManager.friends.count,
            flashbacksCount: flashbackManager.flashbacks.count
          )
          .padding(.horizontal)
          .padding(.top, 8)

          if flashbackManager.flashbacks.isEmpty && !flashbackManager.isLoading {
            ContentUnavailableView(
              "No Flashbacks Yet",
              systemImage: "photo.on.rectangle.angled",
              description: Text("Flashbacks you create will appear here.")
            )
            .padding(.top, 40)
          } else {
            LazyVGrid(columns: columns, spacing: 12) {
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
            .padding(.horizontal)
          }
        }
      }
      .navigationTitle(profile?.username.map { "@\($0)" } ?? "Profile")
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
    VStack(alignment: .leading, spacing: 16) {
      HStack(alignment: .center, spacing: 24) {
        AvatarView(
          urlPath: profile?.avatarUrl,
          name: profile?.displayName ?? "Unknown",
          size: 88
        )

        HStack(spacing: 0) {
          ProfileStatView(count: flashbacksCount, label: "Flashbacks")
            .frame(maxWidth: .infinity)
          NavigationLink {
            FriendsView()
          } label: {
            ProfileStatView(count: friendsCount, label: "Friends")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.plain)
        }
      }

      if let fullName = profile?.fullName,
         !fullName.isEmpty,
         fullName != profile?.username {
        Text(fullName)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.primary)
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
        .font(.title3.weight(.semibold))
        .foregroundStyle(.primary)
      Text(label)
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
  }
}

struct FlashbackGridItemView: View {
  let flashback: Flashback

  var body: some View {
    GeometryReader { geometry in
      ZStack(alignment: .bottomLeading) {
        // Cover image or default
        Group {
          if let coverPath = flashback.coverThumbnailPath ?? flashback.coverImagePath {
            CachedAsyncImage(storagePath: coverPath, contentMode: .fill)
          } else {
            // No photos - show default album icon
            Rectangle()
              .fill(Color(.secondarySystemFill))
              .overlay {
                Image(systemName: "photo.on.rectangle.angled")
                  .font(.system(size: 28))
                  .foregroundStyle(.secondary)
              }
          }
        }
        .frame(width: geometry.size.width, height: geometry.size.width)

        // Scrim for legibility of the name overlay
        LinearGradient(
          colors: [.clear, .black.opacity(0.45)],
          startPoint: .center,
          endPoint: .bottom
        )

        // Name overlay
        Text(flashback.name)
          .font(.caption.weight(.semibold))
          .foregroundStyle(.white)
          .lineLimit(1)
          .padding(.horizontal, 8)
          .padding(.bottom, 8)
      }
      .frame(width: geometry.size.width, height: geometry.size.width)
      .clipped()
      .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
    .aspectRatio(1, contentMode: .fit)
  }
}

#Preview {
    ProfileView()
}
