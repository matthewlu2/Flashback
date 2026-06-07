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

    private static let lastFlashbackKey = "lastSelectedFlashbackId"

    var body: some View {
        ZStack {

            if cameraManager.authorizationStatus == .authorized {
                CameraPreview(session: cameraManager.session).ignoresSafeArea()
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

            VStack {
                // Top bar: flash (left) - album (center) - flip (right)
                HStack {
                    // Flash toggle - top left
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
                    .opacity(cameraManager.isRecording ? 0.4 : 1)

                    Spacer()

                    // Current album selector - centered
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
                    } else {
                        Button {
                            showingFlashbackPicker = true
                        } label: {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(selectedFlashback != nil ? Color.green : Color.gray)
                                    .frame(width: 8, height: 8)
                                    .shadow(color: selectedFlashback != nil ? .green.opacity(0.9) : .clear, radius: 4)

                                Text(selectedFlashback?.name ?? "Choose Flashback")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.white)

                                Image(systemName: "chevron.down")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.8))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                            .shadow(color: .black.opacity(0.25), radius: 4, y: 1)
                        }
                    }

                    Spacer()

                    // Flip Camera Button - top right
                    Button {
                        cameraManager.flipCamera()
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath.camera")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                            .shadow(color: .black.opacity(0.45), radius: 3, y: 1)
                    }
                    .disabled(cameraManager.isRecording)
                    .opacity(cameraManager.isRecording ? 0.4 : 1)
                }
                .padding(.horizontal, 20)
                .padding(.top, 60)

                Spacer()

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
            .sheet(item: $cameraManager.capturedImage) { item in
                MediaPreviewView(
                    media: .photo(item.image),
                    selectedFlashback: selectedFlashback,
                    onDismiss: {
                        cameraManager.capturedImage = nil
                    }
                )
            }
            .onChange(of: cameraManager.capturedVideoURL) { _, newURL in
                // Video capture is handled via onChange since URL isn't Identifiable
            }
            .sheet(isPresented: Binding(
                get: { cameraManager.capturedVideoURL != nil },
                set: { if !$0 { cameraManager.capturedVideoURL = nil } }
            )) {
                if let url = cameraManager.capturedVideoURL {
                    MediaPreviewView(
                        media: .video(url),
                        selectedFlashback: selectedFlashback,
                        onDismiss: {
                            cameraManager.capturedVideoURL = nil
                        }
                    )
                }
            }
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
}

// MARK: - Shutter Button

private struct ShutterButton: View {
    let isRecording: Bool
    let onTap: () -> Void
    let onLongPressStart: () -> Void
    let onLongPressEnd: () -> Void

    @State private var isPressed = false
    @State private var longPressTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            // Outer ring
            Circle()
                .stroke(isRecording ? .red : .white, lineWidth: 4)
                .frame(width: 74, height: 74)

            // Inner circle
            if isRecording {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.red)
                    .frame(width: 32, height: 32)
            } else {
                Circle()
                    .fill(.white.opacity(isPressed ? 0.45 : 0.85))
                    .frame(width: 60, height: 60)
                    .scaleEffect(isPressed ? 0.88 : 1.0)
            }
        }
        .shadow(color: .black.opacity(0.3), radius: 6)
        .animation(.easeOut(duration: 0.15), value: isPressed)
        .animation(.easeOut(duration: 0.15), value: isRecording)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed && !isRecording {
                        isPressed = true
                        longPressTask = Task {
                            try? await Task.sleep(for: .milliseconds(300))
                            if !Task.isCancelled {
                                await MainActor.run {
                                    onLongPressStart()
                                }
                            }
                        }
                    }
                }
                .onEnded { _ in
                    isPressed = false
                    longPressTask?.cancel()

                    if isRecording {
                        onLongPressEnd()
                    } else {
                        onTap()
                    }
                }
        )
    }
}


#Preview {
    CameraView()
}

