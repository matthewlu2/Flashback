//
//  AuthTheme.swift
//  Flashback
//
//  Shared black-and-white styling for the authentication screens.
//

import SwiftUI
import AuthenticationServices

// MARK: - Background

struct AuthBackground: View {
    var body: some View {
        Color.black.ignoresSafeArea()
    }
}

// MARK: - Field styling

extension View {
    func authFieldStyle(focused: Bool) -> some View {
        self
            .padding()
            .background(Color.white.opacity(0.05))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(focused ? Color.white.opacity(0.4) : Color.white.opacity(0.12), lineWidth: 1)
            )
            .foregroundStyle(.white)
            .tint(.white)
    }
}

/// A labeled text or secure field styled for the dark auth screens.
struct AuthTextField<Field: Hashable>: View {
    let label: String
    let prompt: String
    @Binding var text: String
    var isSecure: Bool = false
    var textContentType: UITextContentType? = nil
    var keyboardType: UIKeyboardType = .default
    var autocapitalization: TextInputAutocapitalization = .sentences
    var disableAutocorrection: Bool = false
    let field: Field
    var focus: FocusState<Field?>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.gray)

            Group {
                if isSecure {
                    SecureField("", text: $text, prompt: promptText)
                } else {
                    TextField("", text: $text, prompt: promptText)
                }
            }
            .textContentType(textContentType)
            .keyboardType(keyboardType)
            .textInputAutocapitalization(autocapitalization)
            .autocorrectionDisabled(disableAutocorrection)
            .focused(focus, equals: field)
            .authFieldStyle(focused: focus.wrappedValue == field)
        }
    }

    private var promptText: Text {
        Text(prompt).foregroundColor(.gray.opacity(0.5))
    }
}

// MARK: - Primary button

struct AuthPrimaryButton: View {
    let title: String
    var isLoading: Bool = false
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .black))
                        .scaleEffect(0.9)
                } else {
                    Text(title)
                        .fontWeight(.semibold)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(isEnabled ? Color.white : Color.white.opacity(0.3))
            .foregroundColor(.black)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .disabled(!isEnabled || isLoading)
    }
}

// MARK: - Error banner

struct AuthErrorBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
            Text(message)
                .font(.caption)
        }
        .foregroundColor(.red.opacity(0.9))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.red.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - OAuth buttons

/// Full-width Google sign-in button built from Google's official button asset.
struct GoogleSignInButton: View {
    var isLoading: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image("google_ctn")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Color.white)
                .clipShape(Capsule())
        }
        .disabled(isLoading)
    }
}

/// Full-width Sign in with Apple button matching the Google button's shape.
struct AppleSignInButton: View {
    let onRequest: (ASAuthorizationAppleIDRequest) -> Void
    let onCompletion: (Result<ASAuthorization, Error>) -> Void

    var body: some View {
        SignInWithAppleButton(.signIn, onRequest: onRequest, onCompletion: onCompletion)
            .signInWithAppleButtonStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .clipShape(Capsule())
    }
}
