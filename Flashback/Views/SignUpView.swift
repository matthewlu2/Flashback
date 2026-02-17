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
    @State var email = ""
    @State var password: String = ""
    @State var isLoading = false
    @State var result: Result<Void, Error>?
    
    var body: some View {
        VStack{
            Form{
                Section {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section {
                    SecureField("Password", text: $password)
                        .textContentType(.newPassword)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section {
                    Button("Sign Up") {
                        signUpButtonTapped()
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
        }
        .preferredColorScheme(.dark)
    }
    func signUpButtonTapped() {
      Task {
        isLoading = true
        defer { isLoading = false }

        do {
          try await supabase.auth.signUp(
              email: email,
              password: password,
              redirectTo: URL(string: "io.supabase.user-management://login-callback")
          )
          result = .success(())
        } catch {
          result = .failure(error)
        }
      }
    }
}



#Preview {
    SignUpView()
}
