//
//  OnboardingView.swift
//  Flashback
//
//  Created by Claude on 6/7/26.
//

import SwiftUI
import PhotosUI

private struct CropImageItem: Identifiable {
    let id = UUID()
    let image: UIImage
}

struct OnboardingView: View {
    /// Called once onboarding is finished so the app can move on to the main experience.
    let onComplete: () -> Void

    @StateObject private var manager = OnboardingManager()
    @State private var step: OnboardingStep = .username
    @State private var hasLoadedInitialStep = false
    @FocusState private var focusedField: Field?
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var cropImageItem: CropImageItem?

    private enum Field: Hashable {
        case username
        case phone
    }

    var body: some View {
        ZStack {
            AuthBackground()

            VStack(spacing: 0) {
                switch step {
                case .username:
                    usernameStep
                case .photo:
                    photoStep
                case .phone:
                    phoneStep
                case .friends:
                    friendsStep
                }
            }
            .padding(.horizontal, 24)
        }
        .task {
            guard !hasLoadedInitialStep else { return }
            step = await manager.loadInitialStep()
            hasLoadedInitialStep = true
        }
        .fullScreenCover(item: $cropImageItem) { item in
            AvatarCropView(
                image: item.image,
                onConfirm: { cropped in
                    manager.selectedImage = cropped
                    cropImageItem = nil
                    photoPickerItem = nil
                },
                onCancel: {
                    cropImageItem = nil
                    photoPickerItem = nil
                }
            )
        }
    }

    // MARK: - Username step

    private var usernameStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer()

            VStack(alignment: .leading, spacing: 12) {
                Text("Choose a username")
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)
                Text("This is how friends will find you on Flashback.")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }

            AuthTextField(
                label: "USERNAME",
                prompt: "yourname",
                text: $manager.username,
                textContentType: .username,
                keyboardType: .asciiCapable,
                autocapitalization: .never,
                disableAutocorrection: true,
                field: Field.username,
                focus: $focusedField
            )
            .onChange(of: manager.username) { _, _ in
                manager.scheduleUsernameAvailabilityCheck()
            }

            usernameAvailabilityHint

            if let error = manager.usernameError {
                AuthErrorBanner(message: error)
            }

            Spacer()

            AuthPrimaryButton(
                title: "Continue",
                isLoading: manager.isSavingUsername,
                isEnabled: canContinueFromUsername
            ) {
                Task {
                    if await manager.saveUsername() {
                        withAnimation { step = .photo }
                    }
                }
            }
            .padding(.bottom, 24)
        }
    }

    @ViewBuilder
    private var usernameAvailabilityHint: some View {
        if let validationError = UsernameValidator.validationError(for: manager.username) {
            Text(validationError)
                .font(.caption)
                .foregroundColor(.gray)
        } else if manager.isCheckingUsername {
            Text("Checking availability…")
                .font(.caption)
                .foregroundColor(.gray)
        } else if manager.isUsernameAvailable == true {
            Text("Available")
                .font(.caption)
                .foregroundColor(.green.opacity(0.9))
        } else if manager.isUsernameAvailable == false {
            Text("Already taken")
                .font(.caption)
                .foregroundColor(.red.opacity(0.9))
        }
    }

    private var canContinueFromUsername: Bool {
        UsernameValidator.validationError(for: manager.username) == nil
            && manager.isUsernameAvailable == true
            && !manager.isCheckingUsername
    }

    @ViewBuilder
    private var phoneAvailabilityHint: some View {
        if let validationError = PhoneValidator.validationError(for: manager.rawPhone) {
            Text(validationError)
                .font(.caption)
                .foregroundColor(.gray)
        } else if manager.isCheckingPhone {
            Text("Checking availability…")
                .font(.caption)
                .foregroundColor(.gray)
        } else if manager.isPhoneAvailable == true {
            Text("Available")
                .font(.caption)
                .foregroundColor(.green.opacity(0.9))
        } else if manager.isPhoneAvailable == false {
            Text("Already linked to another account")
                .font(.caption)
                .foregroundColor(.red.opacity(0.9))
        }
    }

    private var canContinueFromPhone: Bool {
        PhoneValidator.validatedNormalized(manager.rawPhone) != nil
            && manager.isPhoneAvailable == true
            && !manager.isCheckingPhone
    }

    // MARK: - Photo step

    private var photoStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer()

            VStack(alignment: .leading, spacing: 12) {
                Text("Add a profile photo")
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)
                Text("Help friends recognize you. You can change this later.")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }

            HStack {
                Spacer()
                photoPreview
                Spacer()
            }
            .padding(.vertical, 8)

            HStack {
                Spacer()
                PhotosPicker(selection: $photoPickerItem, matching: .images) {
                    Text("Choose Photo")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )
                }
                Spacer()
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

            if let error = manager.avatarError {
                AuthErrorBanner(message: error)
            }

            Spacer()

            VStack(spacing: 16) {
                AuthPrimaryButton(
                    title: "Continue",
                    isLoading: manager.isUploadingAvatar,
                    isEnabled: true
                ) {
                    Task {
                        if await manager.uploadAvatarIfNeeded() {
                            withAnimation { step = .phone }
                        }
                    }
                }

                Button("Skip for now") {
                    Task {
                        await manager.markPhotoStepCompleted()
                        withAnimation { step = .phone }
                    }
                }
                .font(.subheadline.weight(.medium))
                .foregroundColor(.gray)
            }
            .padding(.bottom, 24)
        }
    }

    private func loadPickerImage(from item: PhotosPickerItem) async -> UIImage? {
        if let data = try? await item.loadTransferable(type: Data.self),
           let image = UIImage(data: data) {
            return image
        }
        return nil
    }

    @ViewBuilder
    private var photoPreview: some View {
        if let image = manager.selectedImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 120, height: 120)
                .clipShape(Circle())
        } else {
            AvatarView(
                urlPath: manager.existingAvatarUrl,
                name: manager.username.isEmpty ? "?" : manager.username,
                size: 120
            )
        }
    }

    // MARK: - Phone step

    private var phoneStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer()

            VStack(alignment: .leading, spacing: 12) {
                Text("What's your number?")
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)
                Text("We use your phone number to help friends find you on Flashback. We never send texts or share it.")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }

            AuthTextField(
                label: "PHONE NUMBER",
                prompt: "(555) 123-4567",
                text: $manager.rawPhone,
                textContentType: .telephoneNumber,
                keyboardType: .phonePad,
                field: Field.phone,
                focus: $focusedField
            )
            .onChange(of: manager.rawPhone) { _, _ in
                manager.schedulePhoneAvailabilityCheck()
            }

            phoneAvailabilityHint

            if let error = manager.phoneError {
                AuthErrorBanner(message: error)
            }

            Spacer()

            AuthPrimaryButton(
                title: "Continue",
                isLoading: manager.isSavingPhone,
                isEnabled: canContinueFromPhone
            ) {
                Task {
                    if await manager.savePhone() {
                        withAnimation { step = .friends }
                    }
                }
            }
            .padding(.bottom, 24)
        }
    }

    // MARK: - Friends step

    private var friendsStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Find your friends")
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)
                Text("Connect your contacts to discover friends already using Flashback.")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            .padding(.top, 60)

            if !manager.contactsAuthorized {
                AuthPrimaryButton(
                    title: "Allow Contacts",
                    isLoading: manager.isMatchingContacts
                ) {
                    Task { await manager.requestContactsAndMatch() }
                }
            }

            if manager.isMatchingContacts {
                HStack {
                    ProgressView().tint(.white)
                    Text("Looking for friends...")
                        .foregroundColor(.gray)
                        .font(.subheadline)
                }
                .padding(.top, 8)
            }

            if manager.contactsAuthorized && !manager.isMatchingContacts {
                if manager.discovered.isEmpty {
                    Text("No contacts are on Flashback yet. You can add friends anytime from your profile.")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .padding(.top, 8)
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(manager.discovered) { profile in
                                DiscoveredFriendRow(
                                    profile: profile,
                                    isSent: manager.sentRequests.contains(profile.id)
                                ) {
                                    Task { await manager.sendRequest(to: profile) }
                                }
                            }
                        }
                    }
                }
            }

            Spacer()

            AuthPrimaryButton(title: "Get Started", isLoading: manager.isFinishing) {
                Task {
                    _ = await manager.finish()
                    onComplete()
                }
            }
            .padding(.bottom, 24)
        }
    }
}

private struct DiscoveredFriendRow: View {
    let profile: PublicProfile
    let isSent: Bool
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(urlPath: profile.avatarUrl, name: profile.displayName, size: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(profile.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                if let fullName = profile.fullName, !fullName.isEmpty, fullName != profile.displayName {
                    Text(fullName)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }

            Spacer()

            Button(action: onAdd) {
                Text(isSent ? "Requested" : "Add")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(isSent ? .gray : .black)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(isSent ? Color.white.opacity(0.1) : Color.white)
                    .clipShape(Capsule())
            }
            .disabled(isSent)
        }
        .padding(12)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
