//
//  SettingsView.swift
//  Flashback
//
//  Created by Matthew Lu on 4/7/26.
//

import SwiftUI
import Supabase

struct SettingsView: View {
    @State var username = ""
    @State var fullName = ""
    @State var website = ""
    @State var isLoading = false
    @State var profileError: String?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
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
