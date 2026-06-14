//
//  OnboardingManager.swift
//  Flashback
//
//  Created by Claude on 6/7/26.
//

import SwiftUI
import Contacts
import Supabase
import Combine

enum OnboardingStep {
    case username
    case photo
    case phone
    case friends
}

@MainActor
class OnboardingManager: ObservableObject {
    @Published var username = ""
    @Published var isSavingUsername = false
    @Published var usernameError: String?
    @Published var isCheckingUsername = false
    @Published var isUsernameAvailable: Bool?

    @Published var selectedImage: UIImage?
    @Published var isUploadingAvatar = false
    @Published var avatarError: String?
    @Published var existingAvatarUrl: String?

    @Published var rawPhone = ""
    @Published var isSavingPhone = false
    @Published var phoneError: String?
    @Published var isCheckingPhone = false
    @Published var isPhoneAvailable: Bool?

    @Published var contactsAuthorized = false
    @Published var isMatchingContacts = false
    @Published var discovered: [PublicProfile] = []
    @Published var sentRequests: Set<UUID> = []

    @Published var isFinishing = false

    private var usernameCheckTask: Task<Void, Never>?
    private var phoneCheckTask: Task<Void, Never>?

    // MARK: - Resume

    func loadInitialStep() async -> OnboardingStep {
        do {
            let me = try await supabase.auth.session.user.id
            let profile: Profile = try await supabase
                .from("profiles")
                .select()
                .eq("id", value: me)
                .single()
                .execute()
                .value

            if let existing = profile.username, !existing.isEmpty {
                username = existing
            }
            existingAvatarUrl = profile.avatarUrl
            if let phone = profile.phone, !phone.isEmpty {
                rawPhone = phone
            }

            if profile.username?.isEmpty != false {
                return .username
            }
            if !hasCompletedPhotoStep(userId: me) {
                return .photo
            }
            if profile.phone?.isEmpty != false {
                return .phone
            }
            return .friends
        } catch {
            print("loadInitialStep error: \(error.localizedDescription)")
            return .username
        }
    }

    // MARK: - Username

    func scheduleUsernameAvailabilityCheck() {
        usernameCheckTask?.cancel()
        usernameError = nil
        isUsernameAvailable = nil

        let normalized = UsernameValidator.normalize(username)
        if let validationError = UsernameValidator.validationError(for: username) {
            usernameError = validationError
            return
        }

        usernameCheckTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            await checkUsernameAvailability(normalized: normalized)
        }
    }

    func checkUsernameAvailability(normalized: String? = nil) async {
        let candidate = normalized ?? UsernameValidator.normalize(username)
        guard UsernameValidator.validationError(for: candidate) == nil else {
            isUsernameAvailable = nil
            return
        }

        isCheckingUsername = true
        defer { isCheckingUsername = false }

        do {
            let me = try await supabase.auth.session.user.id
            struct IdRow: Decodable { let id: UUID }

            let rows: [IdRow] = try await supabase
                .from("profiles")
                .select("id")
                .eq("username", value: candidate)
                .neq("id", value: me)
                .limit(1)
                .execute()
                .value

            isUsernameAvailable = rows.isEmpty
        } catch {
            print("checkUsernameAvailability error: \(error.localizedDescription)")
            isUsernameAvailable = nil
        }
    }

    func saveUsername() async -> Bool {
        usernameError = nil
        let normalized = UsernameValidator.normalize(username)

        if let validationError = UsernameValidator.validationError(for: normalized) {
            usernameError = validationError
            return false
        }

        if isUsernameAvailable != true {
            await checkUsernameAvailability(normalized: normalized)
            if isUsernameAvailable != true {
                usernameError = "Username is already taken."
                return false
            }
        }

        isSavingUsername = true
        defer { isSavingUsername = false }

        do {
            let me = try await supabase.auth.session.user.id
            try await supabase
                .from("profiles")
                .update(["username": normalized])
                .eq("id", value: me)
                .execute()
            username = normalized
            return true
        } catch {
            if UsernameValidator.isDuplicateUsernameError(error) {
                usernameError = "Username is already taken."
            } else {
                usernameError = "Couldn't save your username. Please try again."
            }
            print("saveUsername error: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Avatar

    func markPhotoStepCompleted() async {
        guard let me = try? await supabase.auth.session.user.id else { return }
        UserDefaults.standard.set(true, forKey: photoStepKey(for: me))
    }

    func uploadAvatarIfNeeded() async -> Bool {
        avatarError = nil
        guard let image = selectedImage else {
            await markPhotoStepCompleted()
            return true
        }

        isUploadingAvatar = true
        defer { isUploadingAvatar = false }

        do {
            let userId = try await supabase.auth.session.user.id.uuidString.lowercased()
            let storagePath = "\(userId)/avatar.jpg"
            let downscaled = MediaProcessor.downscaleImage(image, maxDimension: 512)
            guard let imageData = downscaled.jpegData(compressionQuality: 0.85) else {
                avatarError = "Couldn't process that photo. Please try another."
                return false
            }

            try await supabase.storage
                .from("avatars")
                .upload(
                    storagePath,
                    data: imageData,
                    options: .init(contentType: "image/jpeg", upsert: true)
                )

            let publicURL = try supabase.storage
                .from("avatars")
                .getPublicURL(path: storagePath)
                .absoluteString

            let me = try await supabase.auth.session.user.id
            try await supabase
                .from("profiles")
                .update(["avatar_url": publicURL])
                .eq("id", value: me)
                .execute()

            existingAvatarUrl = publicURL
            await markPhotoStepCompleted()
            return true
        } catch {
            avatarError = "Couldn't upload your photo. Please try again."
            print("uploadAvatar error: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Phone

    func schedulePhoneAvailabilityCheck() {
        phoneCheckTask?.cancel()
        phoneError = nil
        isPhoneAvailable = nil

        guard let normalized = PhoneValidator.validatedNormalized(rawPhone) else {
            return
        }

        phoneCheckTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            await checkPhoneAvailability(normalized: normalized)
        }
    }

    func checkPhoneAvailability(normalized: String? = nil) async {
        let candidate = normalized ?? PhoneValidator.validatedNormalized(rawPhone)
        guard let candidate else {
            isPhoneAvailable = nil
            return
        }

        isCheckingPhone = true
        defer { isCheckingPhone = false }

        do {
            let me = try await supabase.auth.session.user.id
            struct IdRow: Decodable { let id: UUID }

            let rows: [IdRow] = try await supabase
                .from("profiles")
                .select("id")
                .eq("phone_normalized", value: candidate)
                .neq("id", value: me)
                .limit(1)
                .execute()
                .value

            isPhoneAvailable = rows.isEmpty
        } catch {
            print("checkPhoneAvailability error: \(error.localizedDescription)")
            isPhoneAvailable = nil
        }
    }

    func savePhone() async -> Bool {
        phoneError = nil
        if let validationError = PhoneValidator.validationError(for: rawPhone) {
            phoneError = validationError
            return false
        }
        guard let normalized = PhoneValidator.validatedNormalized(rawPhone) else {
            phoneError = "Please enter a valid phone number."
            return false
        }

        if isPhoneAvailable != true {
            await checkPhoneAvailability(normalized: normalized)
            if isPhoneAvailable != true {
                phoneError = "This phone number is already linked to another account."
                return false
            }
        }

        isSavingPhone = true
        defer { isSavingPhone = false }

        do {
            let me = try await supabase.auth.session.user.id
            try await supabase
                .from("profiles")
                .update([
                    "phone": rawPhone.trimmingCharacters(in: .whitespacesAndNewlines),
                    "phone_normalized": normalized
                ])
                .eq("id", value: me)
                .execute()
            return true
        } catch {
            if PhoneValidator.isDuplicatePhoneError(error) {
                phoneError = "This phone number is already linked to another account."
            } else {
                phoneError = "Couldn't save your number. Please try again."
            }
            print("savePhone error: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Contacts

    func requestContactsAndMatch() async {
        let store = CNContactStore()
        do {
            let granted = try await store.requestAccess(for: .contacts)
            contactsAuthorized = granted
            guard granted else { return }
            await matchContacts(store: store)
        } catch {
            contactsAuthorized = false
            print("Contacts access error: \(error.localizedDescription)")
        }
    }

    private func matchContacts(store: CNContactStore) async {
        isMatchingContacts = true
        defer { isMatchingContacts = false }

        let normalizedNumbers: [String] = await Task.detached {
            var numbers = Set<String>()
            let keys = [CNContactPhoneNumbersKey as CNKeyDescriptor]
            let request = CNContactFetchRequest(keysToFetch: keys)
            do {
                try store.enumerateContacts(with: request) { contact, _ in
                    for phone in contact.phoneNumbers {
                        if let normalized = PhoneNormalizer.normalize(phone.value.stringValue) {
                            numbers.insert(normalized)
                        }
                    }
                }
            } catch {
                print("Enumerate contacts error: \(error.localizedDescription)")
            }
            return Array(numbers)
        }.value

        do {
            let matches = try await FriendsManager.shared.findFriendsByPhones(normalizedNumbers)
            discovered = matches
        } catch {
            print("findFriendsByPhones error: \(error.localizedDescription)")
        }
    }

    // MARK: - Friend requests

    func sendRequest(to profile: PublicProfile) async {
        do {
            try await FriendsManager.shared.sendRequest(to: profile.id)
            sentRequests.insert(profile.id)
        } catch {
            print("sendRequest error: \(error.localizedDescription)")
        }
    }

    // MARK: - Completion

    func finish() async -> Bool {
        isFinishing = true
        defer { isFinishing = false }
        do {
            let me = try await supabase.auth.session.user.id
            try await supabase
                .from("profiles")
                .update(["onboarding_completed": true])
                .eq("id", value: me)
                .execute()
            return true
        } catch {
            print("finish onboarding error: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Helpers

    private func photoStepKey(for userId: UUID) -> String {
        "onboardingPhotoStepCompleted_\(userId.uuidString.lowercased())"
    }

    private func hasCompletedPhotoStep(userId: UUID) -> Bool {
        UserDefaults.standard.bool(forKey: photoStepKey(for: userId))
    }
}
