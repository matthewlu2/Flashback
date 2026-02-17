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

struct AuthView: View {
  @State var email = ""
  @State var password = ""
  @State var isLoading = false
  @State var result: Result<Void, Error>?

  var body: some View {
      NavigationStack {
          VStack {
              Form {
                  Section {
                      TextField("Email", text: $email)
                          .textContentType(.emailAddress)
                          .textInputAutocapitalization(.never)
                          .autocorrectionDisabled()
                  }
                  Section {
                      SecureField("Password", text: $password)
                          .textContentType(.password)
                          .textInputAutocapitalization(.never)
                          .autocorrectionDisabled()
                  }
                  Section {
                      Button("Sign in") {
                          signInButtonTapped()
                      }
                      if isLoading {
                          ProgressView()
                      }
                  }
                  if let result {
                      Section {
                          switch result {
                          case .success:
                              Text("Check your inbox.")
                          case .failure(let error):
                              Text(error.localizedDescription).foregroundStyle(.red)
                          }
                      }
                  }
              }
              .onOpenURL(perform: { url in
                  Task {
                      do {
                          try await supabase.auth.session(from: url)
                      } catch {
                          self.result = .failure(error)
                      }
                  }
              })

              HStack {
                  Section {
                      GoogleSignInButton() {
                          Task {
                              do {
                                  try await googleSignIn()
                                  result = .success(())
                              } catch {
                                  result = .failure(error)
                              }
                          }
                      }
                      .clipShape(Capsule())
                      
                  }
                  .listRowBackground(Color.clear)
                  .listRowInsets(EdgeInsets())
                  Section {
                      SignInWithAppleButton(
                        .signIn,
                        onRequest: { request in
                            request.requestedScopes = [.fullName, .email]
                        },
                        onCompletion: { result in
                            print(result)
                        }
                      )
                      .clipShape(Capsule())
                  }
                  .listRowBackground(Color.clear)
                  .listRowInsets(EdgeInsets())
                  .frame(height: 40)
              }
              .listRowBackground(Color.clear)
              .listRowInsets(EdgeInsets())
              
              Spacer(minLength: 30)
                                    
              NavigationLink("Sign Up") {
                  SignUpView()
              }
              .padding(.bottom, 10)
          }
      }
      .preferredColorScheme(.dark)
  }

  func signInButtonTapped() {
    Task {
      isLoading = true
      defer { isLoading = false }

      do {
        try await supabase.auth.signIn(
            email: email,
            password: password,
//            redirectTo: URL(string: "io.supabase.user-management://login-callback")
        )
        result = .success(())
      } catch {
        result = .failure(error)
      }
    }
  }
    
  func googleSignIn() async throws {
      guard let presentingVC = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?
          .windows.first?.rootViewController else {
          print("No root view controller found.")
          return
      }
      
      let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presentingVC)
      
      guard let idToken = result.user.idToken?.tokenString else {
          print("No idToken found.")
          return
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

}

#Preview {
    AuthView()
}
