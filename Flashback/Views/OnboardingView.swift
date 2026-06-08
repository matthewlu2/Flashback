//
//  OnboardingView.swift
//  Flashback
//
//  Created by Claude on 6/7/26.
//

import SwiftUI

struct OnboardingView: View {
    /// Called once onboarding is finished so the app can move on to the main experience.
    let onComplete: () -> Void

    @StateObject private var manager = OnboardingManager()
    @State private var step: Step = .phone
    @FocusState private var focusedField: PhoneField?

    private enum Step {
        case phone
        case friends
    }

    private enum PhoneField {
        case phone
    }

    var body: some View {
        ZStack {
            AuthBackground()

            VStack(spacing: 0) {
                switch step {
                case .phone:
                    phoneStep
                case .friends:
                    friendsStep
                }
            }
            .padding(.horizontal, 24)
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
                field: .phone,
                focus: $focusedField
            )

            if let error = manager.phoneError {
                AuthErrorBanner(message: error)
            }

            Spacer()

            AuthPrimaryButton(
                title: "Continue",
                isLoading: manager.isSavingPhone,
                isEnabled: !manager.rawPhone.trimmingCharacters(in: .whitespaces).isEmpty
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
