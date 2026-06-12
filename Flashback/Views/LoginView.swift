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
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var appleCoordinator = AppleSignInCoordinator()


    var body: some View {
        NavigationStack {
            ZStack {
                AuthBackground()

                VStack(spacing: 0) {
                    Spacer()

                    // Branding
                    VStack(spacing: 16) {
                        Image("FlashbackLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 120, height: 120)

                        Text("Flashback")
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .foregroundColor(.white)

                        VStack(spacing: 8) {
                            Text("Capture moments. Relive memories.")
                                .font(.headline)
                                .foregroundColor(.white)

                            Text("Share photos with friends and revisit your favorite flashbacks together.")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.6))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        }
                    }

                    Spacer()

                    // Authentication
                    VStack(spacing: 16) {
                        if let errorMessage {
                            AuthErrorBanner(message: errorMessage)
                        }

//                        GoogleSignInButton(isLoading: isLoading) {
//                            Task { await signInWithSocial(provider: .google) }
//                        }
                        
//                        AppleSignInButton { request in
//                            request.requestedScopes = [.fullName, .email]
//                        } onCompletion: { result in
//                            handleAppleSignIn(result)
//                        }
                        
                        SocialSignInButton(logo: .apple, title: "Sign in with Apple") {
                            appleCoordinator.signIn { result in
                                handleAppleSignIn(result)
                            }
                        }

                        SocialSignInButton(logo: .google,
                                           title: "Sign in with Google",
                                           isLoading: isLoading) {
                            Task { await signInWithSocial(provider: .google) }
                        }


                        NavigationLink {
                            EmailSignInView()
                        } label: {
                            Text("Sign in with email")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                        }
                    }
                    .padding(.horizontal, 24)

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
                    .padding(.top, 8)
                    .padding(.bottom, 32)
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
        }
        .preferredColorScheme(.dark)
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

struct SocialSignInButton: View {
    enum Logo { case apple, google }

    let logo: Logo
    let title: String
    var isLoading: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.black)
                } else {
                    HStack(spacing: 12) {
                        logoView
                            .frame(width: 20, height: 20)

                        Text(title)
                            .font(.system(size: 17, weight: .medium))
                            .foregroundColor(.black)
                    }
                }
            }
            .frame(maxWidth: .infinity)   // identical width
            .frame(height: 45)            // identical height
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )
        }
        .disabled(isLoading)
    }

    @ViewBuilder
    private var logoView: some View {
        switch logo {
        case .apple:
            Image(systemName: "apple.logo")   // Apple's approved mark
                .resizable()
                .scaledToFit()
                .foregroundColor(.black)
        case .google:
            Image("GoogleLogo")               // official multicolor "G" asset
                .resizable()
                .scaledToFit()
        }
    }
}

final class AppleSignInCoordinator: NSObject,
    ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding {

    private var completion: ((Result<ASAuthorization, Error>) -> Void)?

    func signIn(completion: @escaping (Result<ASAuthorization, Error>) -> Void) {
        self.completion = completion
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithAuthorization authorization: ASAuthorization) {
        completion?(.success(authorization))
    }

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithError error: Error) {
        completion?(.failure(error))
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        (UIApplication.shared.connectedScenes.first as? UIWindowScene)?
            .windows.first ?? ASPresentationAnchor()
    }
}


#Preview {
    LoginView()
}
