//
//  AppView.swift
//  Flashback
//
//  Created by Matthew Lu on 1/28/26.
//

import Foundation
import SwiftUI
import Supabase

struct AppView: View {
  private enum Phase {
    case loading
    case unauthenticated
    case onboarding
    case ready
  }

  @State private var phase: Phase = .loading
  @State private var currentUserId: UUID?
  @StateObject private var inviteManager = InviteManager.shared

  var body: some View {
    Group {
      switch phase {
      case .loading:
        ZStack {
          Color.black.ignoresSafeArea()
          ProgressView().tint(.white)
        }
      case .unauthenticated:
        LoginView()
      case .onboarding:
        OnboardingView {
          phase = .ready
          Task { await inviteManager.processPendingJoinIfNeeded() }
        }
      case .ready:
        ContentView()
      }
    }
    .task {
      for await state in supabase.auth.authStateChanges {
        if [.initialSession, .signedIn, .signedOut].contains(state.event) {
          if let session = state.session {
            let newUserId = session.user.id
            // If the signed-in account changed, drop any cached state from the previous user.
            if currentUserId != newUserId {
              currentUserId = newUserId
              FlashbackManager.shared.reset()
              FriendsManager.shared.reset()
            }
            await resolveAuthenticatedPhase()
          } else {
            currentUserId = nil
            FlashbackManager.shared.reset()
            FriendsManager.shared.reset()
            phase = .unauthenticated
          }
        }
      }
    }
    .onChange(of: phase) { _, newValue in
      if newValue == .ready {
        Task { await inviteManager.processPendingJoinIfNeeded() }
      }
    }
    .onOpenURL { url in
      inviteManager.handle(url: url)
      if phase == .ready {
        Task { await inviteManager.processPendingJoinIfNeeded() }
      }
    }
    .alert("Flashback", isPresented: Binding(
      get: { inviteManager.joinMessage != nil },
      set: { if !$0 { inviteManager.joinMessage = nil } }
    )) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(inviteManager.joinMessage ?? "")
    }
  }

  private func resolveAuthenticatedPhase() async {
    do {
      let me = try await supabase.auth.session.user.id
      let profile: Profile = try await supabase
        .from("profiles")
        .select()
        .eq("id", value: me)
        .single()
        .execute()
        .value

      phase = (profile.onboardingCompleted ?? false) ? .ready : .onboarding
    } catch {
      // If we can't read the profile yet, fall back to onboarding so the user can set things up.
      print("Failed to resolve onboarding state: \(error.localizedDescription)")
      phase = .onboarding
    }
  }
}
