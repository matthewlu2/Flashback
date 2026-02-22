//
//  AuthView.swift
//  Flashback
//
//  Created by Matthew Lu on 1/28/26.
//

import Foundation
import SwiftUI
import Supabase
import AuthenticationServices
import GoogleSignIn
import GoogleSignInSwift

struct LoginView: View {
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
        NavigationStack {
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

                                SecureField("", text: $password, prompt: Text("Password").foregroundColor(.gray.opacity(0.5)))
                                    .textContentType(.password)
                                    .focused($focusedField, equals: .password)
                                    .padding()
                                    .background(Color.white.opacity(0.05))
                                    .cornerRadius(12)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(focusedField == .password ? Color.white.opacity(0.3) : Color.white.opacity(0.1), lineWidth: 1)
                                    )
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

                        // Sign in button
                        Button {
                            signInWithEmail()
                        } label: {
                            HStack(spacing: 8) {
                                if isLoading {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .black))
                                        .scaleEffect(0.8)
                                } else {
                                    Text("Sign In")
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

                        // Divider
                        HStack {
                            Rectangle()
                                .fill(Color.white.opacity(0.1))
                                .frame(height: 1)
                            Text("or continue with")
                                .font(.caption)
                                .foregroundColor(.gray)
                                .fixedSize()
                            Rectangle()
                                .fill(Color.white.opacity(0.1))
                                .frame(height: 1)
                        }
                        .padding(.horizontal, 24)

                        // Social sign-in buttons
                        HStack(spacing: 16) {
                            // Google
                            Button {
                                Task {
                                    await signInWithSocial(provider: .google)
                                }
                            } label: {
                                Image("google_ctn")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(height: 44)
                            }
                            .disabled(isLoading)

                            // Apple
                            SignInWithAppleButton(.signIn) { request in
                                request.requestedScopes = [.fullName, .email]
                            } onCompletion: { result in
                                handleAppleSignIn(result)
                            }
                            .frame(height: 44)
                            .mask(Capsule())
                        }
                        .padding(.horizontal, 32)

                        Spacer(minLength: 40)

                        // Sign up link
                        HStack(spacing: 4) {
                            Text("Don't have an account?")
                                .foregroundColor(.gray)
                            NavigationLink("Sign Up") {
                                SignUpView()
                            }
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                        }
                        .font(.subheadline)
                        .padding(.bottom, 32)
                    }
                }
            }
            .onOpenURL { url in
                Task {
                    do {
                        try await supabase.auth.session(from: url)
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
            .onTapGesture {
                focusedField = nil
            }
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

    private func signInWithSocial(provider: Provider) async {
        isLoading = true
        errorMessage = nil

        defer { isLoading = false }

        do {
            if provider == .google {
                try await signInWithGoogle()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func signInWithGoogle() async throws {
        guard let presentingVC = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?
            .windows.first?.rootViewController else {
            throw AuthError.custom("Unable to find root view controller")
        }

        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presentingVC)

        guard let idToken = result.user.idToken?.tokenString else {
            throw AuthError.custom("Failed to get ID token from Google")
        }

        let accessToken = result.user.accessToken.tokenString

        try await supabase.auth.signInWithIdToken(
            credentials: OpenIDConnectCredentials(
                provider: .google,
                idToken: idToken,
                accessToken: accessToken
            )
        )
    }

    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        Task {
            isLoading = true
            errorMessage = nil

            defer { isLoading = false }

            switch result {
            case .success(let authorization):
                guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                      let identityToken = credential.identityToken,
                      let idTokenString = String(data: identityToken, encoding: .utf8) else {
                    errorMessage = "Failed to get Apple ID credentials"
                    return
                }

                do {
                    try await supabase.auth.signInWithIdToken(
                        credentials: OpenIDConnectCredentials(
                            provider: .apple,
                            idToken: idTokenString
                        )
                    )
                } catch {
                    errorMessage = error.localizedDescription
                }

            case .failure(let error):
                // User cancelled is not an error we need to show
                if (error as NSError).code != ASAuthorizationError.canceled.rawValue {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

// Custom error type for auth
private enum AuthError: LocalizedError {
    case custom(String)

    var errorDescription: String? {
        switch self {
        case .custom(let message):
            return message
        }
    }
}

#Preview {
    LoginView()
}
