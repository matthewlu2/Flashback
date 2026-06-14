//
//  SettingsView.swift
//  Flashback
//
//  Created by Matthew Lu on 4/7/26.
//

import SwiftUI
import PhotosUI
import Supabase

private struct CropImageItem: Identifiable {
    let id = UUID()
    let image: UIImage
}

struct SettingsView: View {
    @State var username = ""
    @State var fullName = ""
    @State var website = ""
    @State var isLoading = false
    @State var profileError: String?

    @StateObject private var avatarManager = OnboardingManager()
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var cropImageItem: CropImageItem?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Profile Photo") {
                    HStack {
                        Spacer()
                        VStack(spacing: 12) {
                            avatarPreview

                            PhotosPicker(selection: $photoPickerItem, matching: .images) {
                                Text("Change Photo")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .disabled(avatarManager.isUploadingAvatar)

                            if avatarManager.isUploadingAvatar {
                                ProgressView()
                            }

                            if let avatarError = avatarManager.avatarError {
                                Text(avatarError)
                                    .foregroundStyle(.red)
                                    .font(.caption)
                            }
                        }
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }

                Section("Account Settings") {
                    TextField("Username", text: $username)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                    TextField("Full name", text: $fullName)
                        .textContentType(.name)
                    TextField("Website", text: $website)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                }

                if let profileError {
                    Section {
                        Text(profileError)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }

                Section {
                    Button("Update profile") {
                        updateProfileButtonTapped()
                    }
                    .bold()

                    if isLoading {
                        ProgressView()
                    }
                }

                Section {
                    Button("Sign out", role: .destructive) {
                        Task {
                            try? await supabase.auth.signOut()
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .task {
            await getInitialProfile()
        }
        .onChange(of: photoPickerItem) { _, newItem in
            Task { @MainActor in
                guard let newItem else { return }
                guard let image = await loadPickerImage(from: newItem) else { return }
                // Let PhotosPicker finish dismissing before presenting the crop sheet.
                try? await Task.sleep(nanoseconds: 350_000_000)
                cropImageItem = CropImageItem(image: image)
            }
        }
        .fullScreenCover(item: $cropImageItem) { item in
            AvatarCropView(
                image: item.image,
                onConfirm: { cropped in
                    cropImageItem = nil
                    photoPickerItem = nil
                    Task {
                        avatarManager.selectedImage = cropped
                        _ = await avatarManager.uploadAvatarIfNeeded()
                        avatarManager.selectedImage = nil
                    }
                },
                onCancel: {
                    cropImageItem = nil
                    photoPickerItem = nil
                }
            )
        }
    }

    @ViewBuilder
    private var avatarPreview: some View {
        if let image = avatarManager.selectedImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 96, height: 96)
                .clipShape(Circle())
        } else {
            AvatarView(
                urlPath: avatarManager.existingAvatarUrl,
                name: username.isEmpty ? (fullName.isEmpty ? "?" : fullName) : username,
                size: 96
            )
        }
    }

    private func loadPickerImage(from item: PhotosPickerItem) async -> UIImage? {
        if let data = try? await item.loadTransferable(type: Data.self),
           let image = UIImage(data: data) {
            return image
        }
        return nil
    }

    func getInitialProfile() async {
        do {
            let currentUser = try await supabase.auth.session.user

            let profile: Profile = try await supabase
                .from("profiles")
                .select()
                .eq("id", value: currentUser.id)
                .single()
                .execute()
                .value

            self.username = profile.username ?? ""
            self.fullName = profile.fullName ?? ""
            self.website = profile.website ?? ""
            avatarManager.username = profile.username ?? ""
            avatarManager.existingAvatarUrl = profile.avatarUrl
        } catch {
            debugPrint(error)
        }
    }

    func updateProfileButtonTapped() {
        Task {
            profileError = nil
            let normalized = UsernameValidator.normalize(username)
            if let validationError = UsernameValidator.validationError(for: normalized) {
                profileError = validationError
                return
            }

            isLoading = true
            defer { isLoading = false }
            do {
                let currentUser = try await supabase.auth.session.user

                try await supabase
                    .from("profiles")
                    .update(
                        UpdateProfileParams(
                            username: normalized,
                            fullName: fullName,
                            website: website
                        )
                    )
                    .eq("id", value: currentUser.id)
                    .execute()
                username = normalized
            } catch {
                if UsernameValidator.isDuplicateUsernameError(error) {
                    profileError = "Username is already taken."
                } else {
                    profileError = "Couldn't update your profile. Please try again."
                }
                debugPrint(error)
            }
        }
    }
}

#Preview {
    SettingsView()
}
