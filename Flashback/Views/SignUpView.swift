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
            // Background gradient
            LinearGradient(
                colors: [Color(white: 0.02), Color(white: 0.1)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 32) {
                    // Header
                    VStack(spacing: 12) {
                        Text("Flashback")
                            .font(.system(size: 42, weight: .bold, design: .rounded))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.white, .white.opacity(0.8)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )

                        Text("Create your account")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    .padding(.top, 60)
                    .padding(.bottom, 20)

                    // Input fields
                    VStack(spacing: 16) {
                        // Email field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Email")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.gray)

                            TextField("", text: $email, prompt: Text("Email").foregroundColor(.gray.opacity(0.5)))
                                .textContentType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(.emailAddress)
                                .focused($focusedField, equals: .email)
                                .padding()
                                .background(Color.white.opacity(0.05))
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(focusedField == .email ? Color.white.opacity(0.3) : Color.white.opacity(0.1), lineWidth: 1)
                                )
                        }

                        // Password field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Password")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.gray)

                            SecureField("", text: $password, prompt: Text("Min. 6 characters").foregroundColor(.gray.opacity(0.5)))
                                .textContentType(.newPassword)
                                .focused($focusedField, equals: .password)
                                .padding()
                                .background(Color.white.opacity(0.05))
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(focusedField == .password ? Color.white.opacity(0.3) : Color.white.opacity(0.1), lineWidth: 1)
                                )
                        }

                        // Confirm Password field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Confirm Password")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.gray)

                            SecureField("", text: $confirmPassword, prompt: Text("Confirm password").foregroundColor(.gray.opacity(0.5)))
                                .textContentType(.newPassword)
                                .focused($focusedField, equals: .confirmPassword)
                                .padding()
                                .background(Color.white.opacity(0.05))
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(focusedField == .confirmPassword ? Color.white.opacity(0.3) : Color.white.opacity(0.1), lineWidth: 1)
                                )
                        }

                        // Password mismatch warning
                        if !confirmPassword.isEmpty && password != confirmPassword {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.circle.fill")
                                Text("Passwords do not match")
                                    .font(.caption)
                            }
                            .foregroundColor(.orange.opacity(0.9))
                        }
                    }
                    .padding(.horizontal, 24)

                    // Error message
                    if let errorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.circle.fill")
                            Text(errorMessage)
                                .font(.caption)
                        }
                        .foregroundColor(.red.opacity(0.9))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                        .padding(.horizontal, 24)
                    }

                    // Success message
                    if showSuccess {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Check your email to confirm your account")
                                .font(.caption)
                        }
                        .foregroundColor(.green.opacity(0.9))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(8)
                        .padding(.horizontal, 24)
                    }

                    // Sign up button
                    Button {
                        signUpButtonTapped()
                    } label: {
                        HStack(spacing: 8) {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .black))
                                    .scaleEffect(0.8)
                            } else {
                                Text("Sign Up")
                                    .fontWeight(.semibold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(isFormValid ? Color.white : Color.white.opacity(0.3))
                        .foregroundColor(.black)
                        .cornerRadius(12)
                    }
                    .disabled(!isFormValid || isLoading)
                    .padding(.horizontal, 24)

                    Spacer(minLength: 40)

                    // Sign in link
                    HStack(spacing: 4) {
                        Text("Already have an account?")
                            .foregroundColor(.gray)
                        Button("Sign In") {
                            dismiss()
                        }
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                    }
                    .font(.subheadline)
                    .padding(.bottom, 32)
                }
            }
        }
        .onTapGesture {
            focusedField = nil
        }
        .preferredColorScheme(.dark)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .foregroundColor(.white)
                }
            }
        }
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
