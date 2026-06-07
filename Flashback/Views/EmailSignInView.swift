//
//  EmailSignInView.swift
//  Flashback
//
//  Created by Matthew Lu on 6/7/26.
//

import Foundation
import SwiftUI
import Supabase

struct EmailSignInView: View {
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?

    private enum Field {
        case email, password
    }

    private var isFormValid: Bool {
        !email.isEmpty && email.contains("@") && password.count >= 1
    }

    var body: some View {
        ZStack {
            AuthBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Welcome back")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundColor(.white)

                        Text("Sign in with your email to continue to Flashback.")
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
                            prompt: "Password",
                            text: $password,
                            isSecure: true,
                            textContentType: .password,
                            field: .password,
                            focus: $focusedField
                        )
                    }

                    if let errorMessage {
                        AuthErrorBanner(message: errorMessage)
                    }

                    AuthPrimaryButton(
                        title: "Sign In",
                        isLoading: isLoading,
                        isEnabled: isFormValid
                    ) {
                        signInWithEmail()
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 24)
            }
        }
        .navigationTitle("Sign In")
        .navigationBarTitleDisplayMode(.inline)
        .onTapGesture {
            focusedField = nil
        }
        .preferredColorScheme(.dark)
    }

    private func signInWithEmail() {
        Task {
            isLoading = true
            errorMessage = nil
            focusedField = nil

            defer { isLoading = false }

            do {
                try await supabase.auth.signIn(
                    email: email,
                    password: password
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

#Preview {
    NavigationStack {
        EmailSignInView()
    }
}
