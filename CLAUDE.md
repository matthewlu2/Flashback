# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Flashback is an iOS photo-sharing app built with SwiftUI. It uses Supabase for backend/authentication and supports Google Sign-In and Apple Sign-In.

## Build & Run

Open `Flashback.xcodeproj` in Xcode and run on a simulator or device. Swift Package Manager handles dependencies automatically.

## Architecture

**Entry Point Flow:**
- `FlashbackApp.swift` -> `AppView` -> (authenticated) `ContentView` / (unauthenticated) `LoginView`

**AppView (`Views/AppView.swift`)** is the auth gate - it listens to `supabase.auth.authStateChanges` and switches between authenticated and unauthenticated views.

**ContentView (`Views/ContentView.swift`)** is a TabView with three tabs:
- Home (placeholder)
- Camera (photo capture)
- Profile (user settings, sign out)

**Camera System:**
- `CameraManager.swift` - ObservableObject wrapping AVFoundation (AVCaptureSession, photo capture)
- `CameraView.swift` - UI for camera preview and capture button
- `CameraPreview.swift` - UIViewRepresentable for AVCaptureVideoPreviewLayer
- `PhotoPreviewView.swift` - displays captured photo

**Authentication:**
- `LoginView.swift` / `SignUpView.swift` - email/password + OAuth (Google, Apple)
- Uses Supabase's OpenIDConnect for social auth

**Backend:**
- `Services/Supabase.swift` - global `supabase` client singleton
- `Models/Models.swift` - `Profile` and `UpdateProfileParams` for the profiles table

## Key Dependencies

- **supabase-swift** - Backend, auth, database
- **GoogleSignIn-iOS** - Google OAuth
- **AuthenticationServices** (system) - Apple Sign-In
- **AVFoundation** (system) - Camera capture
