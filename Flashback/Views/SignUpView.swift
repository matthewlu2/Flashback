//
//  SignUpView.swift
//  Flashback
//
//  Created by Matthew Lu on 2/9/26.
//

import Foundation
import SwiftUI
import Supabase
import AuthenticationServices

struct SignUpView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showSuccess = false
    @FocusState private var focusedField: Field?

    private enum Field {
        case email, password, confirmPassword
    }

    private var isFormValid: Bool {
        !email.isEmpty && email.contains("@") && password.count >= 6 && password == confirmPassword
    }

    var body: some View {
        ZStack {
            AuthBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Create your account")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundColor(.white)

                        Text("Join Flashback and start sharing memories.")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    .padding(.top, 24)

                    VStack(spacing: 16) {
                        AuthTextField(
                            label: "Email",
                            prompt: "Email",
                            text: $email,
                            textContentType: .emailAddress,
                            keyboardType: .emailAddress,
                            autocapitalization: .never,
                            disableAutocorrection: true,
                            field: .email,
                            focus: $focusedField
                        )

                        AuthTextField(
                            label: "Password",
                            prompt: "Min. 6 characters",
                            text: $password,
                            isSecure: true,
                            textContentType: .newPassword,
                            field: .password,
                            focus: $focusedField
                        )

                        AuthTextField(
                            label: "Confirm Password",
                            prompt: "Confirm password",
                            text: $confirmPassword,
                            isSecure: true,
                            textContentType: .newPassword,
                            field: .confirmPassword,
                            focus: $focusedField
                        )

                        if !confirmPassword.isEmpty && password != confirmPassword {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.circle.fill")
                                Text("Passwords do not match")
                                    .font(.caption)
                            }
                            .foregroundColor(.orange.opacity(0.9))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    if let errorMessage {
                        AuthErrorBanner(message: errorMessage)
                    }

                    if showSuccess {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Check your email to confirm your account")
                                .font(.caption)
                        }
                        .foregroundColor(.green.opacity(0.9))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.green.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    AuthPrimaryButton(
                        title: "Sign Up",
                        isLoading: isLoading,
                        isEnabled: isFormValid
                    ) {
                        signUpButtonTapped()
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 24)
            }
        }
        .onTapGesture {
            focusedField = nil
        }
        .preferredColorScheme(.dark)
        .navigationTitle("Sign Up")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func signUpButtonTapped() {
        Task {
            isLoading = true
            errorMessage = nil
            showSuccess = false
            focusedField = nil

            defer { isLoading = false }

            do {
                try await supabase.auth.signUp(
                    email: email,
                    password: password,
                    redirectTo: URL(string: "io.supabase.user-management://login-callback")
                )
                showSuccess = true
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

#Preview {
    NavigationStack {
        SignUpView()
    }
}
