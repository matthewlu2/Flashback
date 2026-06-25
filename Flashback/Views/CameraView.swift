//
//  CameraView.swift
//  Flashback
//
//  Created by Matthew Lu on 2/26/26.
//

import SwiftUI
import AVFoundation
import AVKit

struct CameraView: View {
    @StateObject private var cameraManager = CameraManager()
    @StateObject private var flashbackManager = FlashbackManager.shared

    @State private var selectedFlashback: Flashback?
    @State private var showingFlashbackPicker = false
    @State private var showingCreateFlashback = false
    @State private var recordingDuration: TimeInterval = 0
    @State private var recordingTimer: Timer?
    @State private var gestureStartZoom: CGFloat = 1.0
    @State private var isPinching = false

    // Tap-to-focus indicator
    @State private var focusPoint: CGPoint?
    @State private var focusVisible = false
    @State private var focusResetTask: Task<Void, Never>?

    private static let lastFlashbackKey = "lastSelectedFlashbackId"

    var body: some View {
        ZStack {

            if cameraManager.authorizationStatus == .authorized {
                CameraPreview(session: cameraManager.session) { layer in
                    cameraManager.previewLayer = layer
                }
                    .contentShape(Rectangle())
                    .gesture(
                        // Double tap flips; a single tap focuses where you touch.
                        SpatialTapGesture(count: 2)
                            .onEnded { _ in flipCamera() }
                            .exclusively(before:
                                SpatialTapGesture(count: 1)
                                    .onEnded { value in handleFocusTap(at: value.location) }
                            )
                    )
                    .simultaneousGesture(
                        MagnificationGesture()
                            .onChanged { scale in
                                if !isPinching {
                                    isPinching = true
                                    gestureStartZoom = cameraManager.displayZoom
                                }
                                cameraManager.setZoom(display: gestureStartZoom * scale)
                            }
                            .onEnded { _ in
                                isPinching = false
                            }
                    )

                // Tap-to-focus indicator
                if let focusPoint {
                    FocusReticle()
                        .position(focusPoint)
                        .opacity(focusVisible ? 1 : 0)
                        .allowsHitTesting(false)
                }
            }
            else {
                VStack {
                    Image(systemName: "camera.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.gray)
                    Text("Camera Access Required")
                        .font(.largeTitle)
                        .foregroundStyle(.gray)

                    if cameraManager.authorizationStatus == .denied {
                        Text("Please Enable Camera in Settings")

                        Button("Open Settings") {
                            if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(settingsURL)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }

            // Camera controls — hidden once a shot is captured (review mode).
            if !isReviewing {
                VStack {
                    // Recording timer - top center
                    if cameraManager.isRecording {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 10, height: 10)

                            Text(formatDuration(recordingDuration))
                                .font(.subheadline.monospacedDigit())
                                .fontWeight(.semibold)
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                    }

                    Spacer()
                }
                .padding(.top, 40)

                // Right-side controls: flip (top) - flash - album (bottom)
                VStack {
                  HStack {
                    Spacer()

                    VStack(spacing: 4) {
                        // Flip Camera Button
                        Button {
                            flipCamera()
                        } label: {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                                .shadow(color: .black.opacity(0.45), radius: 3, y: 1)
                        }
                        .disabled(cameraManager.isRecording)
                        .opacity(cameraManager.isRecording ? 0 : 1)

                        // Flash toggle
                        Button {
                            cycleFlashMode()
                        } label: {
                            Image(systemName: flashIconName)
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(flashMode == .on ? .yellow : .white)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                                .shadow(color: .black.opacity(0.45), radius: 3, y: 1)
                        }
                        .disabled(cameraManager.isRecording)
                        .opacity(cameraManager.isRecording ? 0 : 1)

                        // Album selector - circular, green dot indicates a selection
                        Button {
                            showingFlashbackPicker = true
                        } label: {
                            Image(systemName: "rectangle.stack.fill")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                                .shadow(color: .black.opacity(0.45), radius: 3, y: 1)
                                .overlay(alignment: .topTrailing) {
                                    Circle()
                                        .fill(selectedFlashback != nil ? Color.green : Color.gray)
                                        .frame(width: 10, height: 10)
                                        .shadow(color: selectedFlashback != nil ? .green.opacity(0.9) : .clear, radius: 4)
                                        .offset(x: -2, y: 2)
                                }
                        }
                        .disabled(cameraManager.isRecording)
                        .opacity(cameraManager.isRecording ? 0 : 1)
                    }
                    .padding(.trailing, 8)
                  }
                  .padding(.top, 4)

                  Spacer()
                }

                VStack {
                    Spacer()

                    // Zoom controls (hidden while recording)
                    if !cameraManager.isRecording {
                        zoomControl
                            .padding(.bottom, 20)
                            .transition(.opacity)
                    }

                    // Capture Button
                    ShutterButton(
                        isRecording: cameraManager.isRecording,
                        onTap: {
                            cameraManager.capturePhoto()
                        },
                        onLongPressStart: {
                            startRecording()
                        },
                        onLongPressEnd: {
                            stopRecording()
                        }
                    )
                    .padding(.bottom, 40)
                }
                .animation(.easeOut(duration: 0.2), value: cameraManager.isRecording)
            }

            // Inline capture review — replaces the camera once a shot is taken.
            if isReviewing {
                CaptureReviewOverlay(
                    image: cameraManager.capturedImage?.image,
                    videoURL: cameraManager.capturedVideoURL,
                    albumName: selectedFlashback?.name,
                    onRetake: { discardCapture() },
                    onChooseAlbum: { showingFlashbackPicker = true },
                    onSend: { sendCapture() }
                )
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: isReviewing)
        .sheet(isPresented: $showingFlashbackPicker) {
            FlashbackPickerView(
                selectedFlashback: $selectedFlashback,
                showingCreateNew: $showingCreateFlashback
            )
        }
        .sheet(isPresented: $showingCreateFlashback) {
            CreateFlashbackView { flashback in
                selectedFlashback = flashback
            }
        }
        .onAppear {
            cameraManager.checkAuthorization()
        }
        .task {
            await flashbackManager.loadFlashbacksIfNeeded()
            syncSelectedFromDefaults()
        }
        .onChange(of: selectedFlashback?.id) { _, newID in
            if let id = newID {
                UserDefaults.standard.set(id.uuidString, forKey: Self.lastFlashbackKey)
            }
        }
        .onChange(of: cameraManager.capturedImage) { _, newValue in
            if newValue == nil {
                syncSelectedFromDefaults()
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Zoom controls

    @ViewBuilder
    private var zoomControl: some View {
        if cameraManager.currentPosition == .front {
            if cameraManager.frontWideSupported {
                HStack(spacing: 4) {
                    zoomChip(value: 1.0, inactiveLabel: "Wide")
                    zoomChip(value: 1.4, inactiveLabel: "Crop")
                }
                .padding(3)
                .background(Color.black.opacity(0.2))
                .clipShape(Capsule())
            }
        } else if cameraManager.zoomPresets.count > 1 {
            HStack(spacing: 4) {
                ForEach(cameraManager.zoomPresets, id: \.self) { preset in
                    zoomChip(value: preset, inactiveLabel: presetLabel(preset))
                }
            }
            .padding(3)
            .background(Color.black.opacity(0.2))
            .clipShape(Capsule())
        }
    }

    private func zoomChip(value: CGFloat, inactiveLabel: String) -> some View {
        let isActive = isActivePreset(value)
        return Button {
            cameraManager.setZoom(display: value, ramp: true)
        } label: {
            Text(isActive ? activeZoomLabel() : inactiveLabel)
                .font(.system(size: isActive ? 12 : 10, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(isActive ? .yellow : .white)
                .frame(width: isActive ? 32 : 27, height: isActive ? 32 : 27)
                .background(Color.black.opacity(0.25))
                .clipShape(Circle())
        }
    }

    /// The preset nearest to the current zoom is considered active.
    private func isActivePreset(_ preset: CGFloat) -> Bool {
        let presets = cameraManager.zoomPresets
        guard let nearest = presets.min(by: {
            abs($0 - cameraManager.displayZoom) < abs($1 - cameraManager.displayZoom)
        }) else { return false }
        return nearest == preset
    }

    /// Live value shown on the active chip, e.g. "1×" or "2.4×".
    private func activeZoomLabel() -> String {
        let z = cameraManager.displayZoom
        return z == z.rounded() ? "\(Int(z))×" : String(format: "%.1f×", z)
    }

    private func presetLabel(_ preset: CGFloat) -> String {
        preset == preset.rounded() ? "\(Int(preset))" : String(format: "%.1f", preset)
    }

    // MARK: - Camera flip

    private func flipCamera() {
        cameraManager.flipCamera()
    }

    // MARK: - Tap to focus

    private func handleFocusTap(at location: CGPoint) {
        cameraManager.focus(atLayerPoint: location)
        showFocusIndicator(at: location)
    }

    private func showFocusIndicator(at location: CGPoint) {
        focusResetTask?.cancel()
        focusPoint = location
        focusVisible = true

        focusResetTask = Task {
            try? await Task.sleep(for: .seconds(0.5))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.4)) {
                    focusVisible = false
                }
                // Focus stays locked at the tapped point; CameraManager resumes
                // continuous autofocus only when the subject area changes.
            }
        }
    }

    // MARK: - Flash

    private var flashMode: AVCaptureDevice.FlashMode {
        cameraManager.flashMode
    }

    private var flashIconName: String {
        switch cameraManager.flashMode {
        case .on:
            return "bolt.fill"
        case .off:
            return "bolt.slash.fill"
        default:
            return "bolt.badge.a.fill"
        }
    }

    private func cycleFlashMode() {
        switch cameraManager.flashMode {
        case .auto:
            cameraManager.flashMode = .on
        case .on:
            cameraManager.flashMode = .off
        case .off:
            cameraManager.flashMode = .auto
        @unknown default:
            cameraManager.flashMode = .auto
        }
    }

    // MARK: - Recording

    private func startRecording() {
        cameraManager.startRecording()
        recordingDuration = 0
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            recordingDuration += 0.1
        }
    }

    private func stopRecording() {
        cameraManager.stopRecording()
        recordingTimer?.invalidate()
        recordingTimer = nil
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    // MARK: - Album selection

    private func syncSelectedFromDefaults() {
        if let idString = UserDefaults.standard.string(forKey: Self.lastFlashbackKey),
           let id = UUID(uuidString: idString),
           let flashback = flashbackManager.flashbacks.first(where: { $0.id == id }) {
            selectedFlashback = flashback
        }
    }

    // MARK: - Capture review

    /// True while a freshly captured photo/video is being reviewed before sending.
    private var isReviewing: Bool {
        cameraManager.capturedImage != nil || cameraManager.capturedVideoURL != nil
    }

    /// Discards the current capture and returns to the live camera.
    private func discardCapture() {
        if let url = cameraManager.capturedVideoURL {
            try? FileManager.default.removeItem(at: url)
        }
        cameraManager.capturedVideoURL = nil
        cameraManager.capturedImage = nil
    }

    /// Uploads the current capture to the selected album, then returns to the camera.
    /// The upload continues in the background via `UploadManager`.
    private func sendCapture() {
        guard let flashback = selectedFlashback else { return }
        UserDefaults.standard.set(flashback.id.uuidString, forKey: Self.lastFlashbackKey)

        if let image = cameraManager.capturedImage?.image {
            UploadManager.shared.uploadPhoto(image, toFlashback: flashback.id)
        } else if let url = cameraManager.capturedVideoURL {
            UploadManager.shared.uploadVideo(url, toFlashback: flashback.id)
        }

        cameraManager.capturedImage = nil
        cameraManager.capturedVideoURL = nil
    }
}

// MARK: - Capture Review Overlay

/// Shown inline (replacing the camera UI) after a photo/video is captured: the media fills
/// the screen with a Retake control, the destination album picker, and a send arrow.
private struct CaptureReviewOverlay: View {
    let image: UIImage?
    let videoURL: URL?
    let albumName: String?
    let onRetake: () -> Void
    let onChooseAlbum: () -> Void
    let onSend: () -> Void

    @State private var player: AVPlayer?

    private var hasAlbum: Bool { albumName != nil }

    var body: some View {
        ZStack {
            Color.black

            // Captured media
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else if let videoURL {
                VideoPlayer(player: player)
                    .onAppear {
                        let p = AVPlayer(url: videoURL)
                        player = p
                        p.play()
                    }
                    .onDisappear {
                        player?.pause()
                        player = nil
                    }
            }

            // Top bar: Retake
            VStack {
                HStack {
                    Button(action: onRetake) {
                        Image(systemName: "chevron.left")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                            .padding(12)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)

                Spacer()
            }

            // Bottom bar: album picker + send arrow
            VStack {
                Spacer()
                HStack(spacing: 12) {
                    Button(action: onChooseAlbum) {
                        HStack(spacing: 8) {
                            Image(systemName: "rectangle.stack.fill")
                            Text(albumName ?? "Choose Album")
                                .lineLimit(1)
                            Spacer()
                            Image(systemName: "chevron.up")
                                .font(.caption.weight(.bold))
                        }
                        .font(.headline)
                        .foregroundColor(hasAlbum ? .white : .white.opacity(0.75))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                    }

                    Button(action: onSend) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 56, height: 56)
                            .background(hasAlbum ? Color.blue : Color.gray)
                            .clipShape(Circle())
                            .shadow(color: .black.opacity(0.3), radius: 6)
                    }
                    .disabled(!hasAlbum)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
    }
}

// MARK: - Focus Reticle

/// A small white circle shown briefly where the user taps to focus.
private struct FocusReticle: View {
    var body: some View {
        Circle()
            .fill(Color.white.opacity(0.2))
            .overlay(
                Circle().stroke(Color.white, lineWidth: 1.5)
            )
            .frame(width: 44, height: 44)
            .shadow(color: .black.opacity(0.4), radius: 2)
    }
}

// MARK: - Shutter Button

private struct ShutterButton: View {
    let isRecording: Bool
    let onTap: () -> Void
    let onLongPressStart: () -> Void
    let onLongPressEnd: () -> Void

    @State private var isPressed = false
    @State private var isLocked = false
    /// True only for the single release that establishes the lock, so lifting
    /// the finger after a swipe-up doesn't immediately stop the recording.
    @State private var justLocked = false
    @State private var currentTranslation: CGFloat = 0
    @State private var longPressTask: Task<Void, Never>?

    /// How far (points) the finger must travel up while recording to lock.
    private let lockThreshold: CGFloat = 60

    var body: some View {
        ZStack {
            // Outer ring
            Circle()
                .stroke(isRecording ? .red : .white, lineWidth: 4)
                .frame(width: 74, height: 74)

            // Inner circle
            if isRecording {
                Circle()
                    .fill(.red)
                    .frame(width: 32, height: 32)
            } else {
                Circle()
                    .fill(.white.opacity(isPressed ? 0.45 : 0.85))
                    .frame(width: 60, height: 60)
                    .scaleEffect(isPressed ? 0.88 : 1.0)
            }
        }
        .frame(width: 74, height: 74)
        .shadow(color: .black.opacity(0.3), radius: 6)
        .overlay(alignment: .top) {
            // Swipe-up hint while holding; turns into a lock badge once locked.
            if isRecording {
                VStack(spacing: 2) {
                    Image(systemName: isLocked ? "lock.fill" : "chevron.up")
                        .font(.system(size: 13, weight: .bold))
                    Text(isLocked ? "Locked — tap to stop" : "Swipe up to lock")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(isLocked ? .yellow : .white)
                .shadow(color: .black.opacity(0.5), radius: 3)
                .fixedSize()
                .offset(y: -48)
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: isPressed)
        .animation(.easeOut(duration: 0.2), value: isRecording)
        .animation(.easeOut(duration: 0.2), value: isLocked)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    currentTranslation = value.translation.height

                    // While locked, ignore drag movement; a fresh tap (handled
                    // in onEnded) is what stops the recording.
                    guard !isLocked else { return }

                    if !isPressed && !isRecording {
                        isPressed = true
                        longPressTask = Task {
                            try? await Task.sleep(for: .milliseconds(300))
                            guard !Task.isCancelled else { return }
                            await MainActor.run {
                                onLongPressStart()
                                // Catch the case where the user already swiped
                                // up during the hold before recording began.
                                if currentTranslation < -lockThreshold {
                                    lockRecording()
                                }
                            }
                        }
                    }

                    // Swipe far enough up while recording to lock hands-free.
                    if isRecording && value.translation.height < -lockThreshold {
                        lockRecording()
                    }
                }
                .onEnded { _ in
                    longPressTask?.cancel()
                    currentTranslation = 0

                    if isLocked {
                        if justLocked {
                            // This release just engaged the lock; keep recording.
                            justLocked = false
                        } else {
                            // A subsequent tap while locked stops recording.
                            isLocked = false
                            onLongPressEnd()
                        }
                        isPressed = false
                        return
                    }

                    isPressed = false

                    if isRecording {
                        onLongPressEnd()
                    } else {
                        onTap()
                    }
                }
        )
        .onChange(of: isRecording) { _, recording in
            // Reset lock state whenever recording ends for any reason.
            if !recording {
                isLocked = false
                justLocked = false
                isPressed = false
            }
        }
    }

    private func lockRecording() {
        isLocked = true
        justLocked = true
        isPressed = false
    }
}


#Preview {
    CameraView()
}

