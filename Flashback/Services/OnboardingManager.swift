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

@MainActor
class OnboardingManager: ObservableObject {
    @Published var rawPhone = ""
    @Published var isSavingPhone = false
    @Published var phoneError: String?

    @Published var contactsAuthorized = false
    @Published var isMatchingContacts = false
    @Published var discovered: [PublicProfile] = []
    @Published var sentRequests: Set<UUID> = []

    @Published var isFinishing = false

    // MARK: - Phone

    func savePhone() async -> Bool {
        phoneError = nil
        guard let normalized = PhoneNormalizer.normalize(rawPhone) else {
            phoneError = "Please enter a valid phone number."
            return false
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
            phoneError = "Couldn't save your number. Please try again."
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
}
