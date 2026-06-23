//
//  CameraManager.swift
//  Flashback
//
//  Created by Matthew Lu on 2/24/26.
//

import SwiftUI
import AVFoundation
import Combine

class CameraManager: NSObject, ObservableObject {
    @Published var capturedImage: IdentifiableImage?
    @Published var capturedVideoURL: URL?
    @Published var isSessionRunning = false
    @Published var authorizationStatus: AVAuthorizationStatus = .notDetermined
    @Published var currentPosition: AVCaptureDevice.Position = .back
    @Published var flashMode: AVCaptureDevice.FlashMode = .auto
    @Published var isRecording = false

    // Zoom
    @Published var displayZoom: CGFloat = 1.0
    @Published var zoomPresets: [CGFloat] = [1.0]
    @Published var minDisplayZoom: CGFloat = 1.0
    @Published var maxDisplayZoom: CGFloat = 1.0
    @Published var frontWideSupported: Bool = false

    /// Native `videoZoomFactor` that maps to a displayed zoom of `1.0x`.
    private var baseZoomFactor: CGFloat = 1.0

    let session = AVCaptureSession()
    private var photoOutput = AVCapturePhotoOutput()
    private var videoOutput = AVCaptureMovieFileOutput()
    private var currentInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?

    private let sessionQueue = DispatchQueue(label: "com.customcamera.sessionQueue")

    /// Preview layer, supplied by `CameraPreview`, used to convert tap locations
    /// in the view into the camera's normalized point of interest.
    weak var previewLayer: AVCaptureVideoPreviewLayer?

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(subjectAreaDidChange(_:)),
            name: AVCaptureDevice.subjectAreaDidChangeNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    func checkAuthorization() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            authorizationStatus = .authorized
            checkAudioAuthorization()
            
        case .notDetermined:
            authorizationStatus = .notDetermined
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.authorizationStatus = granted ? .authorized : .denied
                    if granted {
                        self?.checkAudioAuthorization()
                    }
                }
            }
        
        case .denied, .restricted:
            authorizationStatus = .denied
            
        @unknown default:
            authorizationStatus = .denied
        }
    }

    private func checkAudioAuthorization() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            setupSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
                self?.setupSession()
            }
        default:
            setupSession()
        }
    }
    
    func setupSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            
            self.session.beginConfiguration()
            self.session.sessionPreset = .high

            // Video input
            guard let camera = self.bestCamera(for: self.currentPosition),
                  let input = try? AVCaptureDeviceInput(device: camera) else {
                print("Failed to access camera")
                self.session.commitConfiguration()
                return
            }

            if self.session.canAddInput(input) {
                self.session.addInput(input)
                self.currentInput = input
            }

            self.configureZoom(for: camera, position: self.currentPosition)

            // Audio input
            if let audioDevice = AVCaptureDevice.default(for: .audio),
               let audioInput = try? AVCaptureDeviceInput(device: audioDevice),
               self.session.canAddInput(audioInput) {
                self.session.addInput(audioInput)
                self.audioInput = audioInput
            }
            
            // Photo output
            if self.session.canAddOutput(self.photoOutput) {
                self.session.addOutput(self.photoOutput)
                if let maxDimensions = camera.activeFormat.supportedMaxPhotoDimensions.last {
                    self.photoOutput.maxPhotoDimensions = maxDimensions
                }
                self.photoOutput.maxPhotoQualityPrioritization = .quality
            }

            // Video output
            if self.session.canAddOutput(self.videoOutput) {
                self.session.addOutput(self.videoOutput)
                if let connection = self.videoOutput.connection(with: .video) {
                    if connection.isVideoStabilizationSupported {
                        connection.preferredVideoStabilizationMode = .auto
                    }
                }
            }
            
            self.session.commitConfiguration()
            self.session.startRunning()
            
            DispatchQueue.main.async {
                self.isSessionRunning = self.session.isRunning
            }
        }
    }
    
    func capturePhoto() {
        let flashMode = self.flashMode

        sessionQueue.async { [weak self] in
            guard let self = self else { return }

            let settings = AVCapturePhotoSettings()
            if self.photoOutput.supportedFlashModes.contains(flashMode) {
                settings.flashMode = flashMode
            }

            // Capture at the current device's full resolution, bounded by what the
            // photo output is configured to support.
            if let maxDimensions = self.currentInput?.device.activeFormat.supportedMaxPhotoDimensions.last {
                settings.maxPhotoDimensions = maxDimensions
            }

            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    func startRecording() {
        guard !isRecording else { return }

        sessionQueue.async { [weak self] in
            guard let self = self else { return }

            // Set video orientation
            if let connection = self.videoOutput.connection(with: .video) {
                if connection.isVideoMirroringSupported && self.currentPosition == .front {
                    connection.isVideoMirrored = true
                }
            }

            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("mp4")

            self.videoOutput.startRecording(to: tempURL, recordingDelegate: self)

            DispatchQueue.main.async {
                self.isRecording = true
            }
        }
    }

    func stopRecording() {
        guard isRecording else { return }

        sessionQueue.async { [weak self] in
            self?.videoOutput.stopRecording()
        }
    }

    func flipCamera() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }

            let newPosition: AVCaptureDevice.Position = self.currentPosition == .back ? .front : .back

            guard let newCamera = self.bestCamera(for: newPosition),
                  let newInput = try? AVCaptureDeviceInput(device: newCamera) else {
                print("Failed to access \(newPosition == .front ? "front" : "back") camera")
                return
            }

            self.session.beginConfiguration()

            if let currentInput = self.currentInput {
                self.session.removeInput(currentInput)
            }

            if self.session.canAddInput(newInput) {
                self.session.addInput(newInput)
                self.currentInput = newInput

                DispatchQueue.main.async {
                    self.currentPosition = newPosition
                }
            }

            self.configureZoom(for: newCamera, position: newPosition)

            self.session.commitConfiguration()
        }
    }

    // MARK: - Focus & Exposure

    /// Focuses (and sets exposure) at a point in the preview's coordinate space.
    /// The point is converted to the camera's normalized device space via the
    /// preview layer before being applied on the session queue.
    func focus(atLayerPoint layerPoint: CGPoint) {
        guard let previewLayer else { return }
        let devicePoint = previewLayer.captureDevicePointConverted(fromLayerPoint: layerPoint)

        sessionQueue.async { [weak self] in
            guard let self, let device = self.currentInput?.device else { return }

            do {
                try device.lockForConfiguration()

                if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(.autoFocus) {
                    device.focusPointOfInterest = devicePoint
                    device.focusMode = .autoFocus
                }

                if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(.autoExpose) {
                    device.exposurePointOfInterest = devicePoint
                    device.exposureMode = .autoExpose
                }

                // Lock onto this point and let the system tell us (via
                // subjectAreaDidChangeNotification) when the scene changes
                // enough to warrant resuming continuous autofocus.
                device.isSubjectAreaChangeMonitoringEnabled = true

                device.unlockForConfiguration()
            } catch {
                print("focus error: \(error.localizedDescription)")
            }
        }
    }

    /// Returns focus and exposure to continuous (full-frame) auto mode, used a
    /// moment after a tap-to-focus so the camera drifts back to tracking.
    func resumeContinuousFocus() {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.currentInput?.device else { return }

            do {
                try device.lockForConfiguration()

                if device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5)
                }
                if device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusMode = .continuousAutoFocus
                }

                if device.isExposurePointOfInterestSupported {
                    device.exposurePointOfInterest = CGPoint(x: 0.5, y: 0.5)
                }
                if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                }

                device.isSubjectAreaChangeMonitoringEnabled = false

                device.unlockForConfiguration()
            } catch {
                print("resumeContinuousFocus error: \(error.localizedDescription)")
            }
        }
    }

    /// Fired when the camera detects the focused subject area has changed
    /// significantly; resume full-frame continuous autofocus.
    @objc private func subjectAreaDidChange(_ notification: Notification) {
        resumeContinuousFocus()
    }

    // MARK: - Device selection

    /// Picks the most capable camera for a position. The back camera uses a virtual
    /// (multi-lens) device when available so the system switches lenses automatically
    /// as `videoZoomFactor` changes.
    private func bestCamera(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        if position == .back {
            return AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: .back)
                ?? AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .back)
                ?? AVCaptureDevice.default(.builtInDualCamera, for: .video, position: .back)
                ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        }
        return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
    }

    // MARK: - Zoom

    /// Inspects a device's lenses (back) or field-of-view formats (front) to build the
    /// preset list, the native↔display mapping, and the pinch range. Must run inside a
    /// session configuration block on `sessionQueue`.
    private func configureZoom(for device: AVCaptureDevice, position: AVCaptureDevice.Position) {
        var base: CGFloat = 1.0
        var presets: [CGFloat] = [1.0]
        var minDisplay: CGFloat = 1.0
        var maxDisplay: CGFloat = 1.0
        var frontWide = false

        if position == .back {
            let lensTypes = device.constituentDevices.map { $0.deviceType }
            let hasUltraWide = lensTypes.contains(.builtInUltraWideCamera)
            let switchOvers = device.virtualDeviceSwitchOverVideoZoomFactors.map { CGFloat(truncating: $0) }

            // With an ultra-wide lens, native 1.0 is the UI "0.5x"; the wide lens (UI "1x")
            // begins at the first switch-over factor.
            if hasUltraWide, let firstSwitch = switchOvers.first {
                base = firstSwitch
            }

            var displayPresets: [CGFloat] = []
            if hasUltraWide {
                displayPresets.append(roundToTenth(device.minAvailableVideoZoomFactor / base))
            }
            displayPresets.append(1.0)
            // Telephoto presets come from switch-over factors beyond the ultra-wide→wide one.
            let telephotoSwitchOvers = hasUltraWide ? Array(switchOvers.dropFirst()) : switchOvers
            for factor in telephotoSwitchOvers {
                displayPresets.append(roundToTenth(factor / base))
            }

            presets = uniqueSorted(displayPresets)
            minDisplay = roundToTenth(device.minAvailableVideoZoomFactor / base)
            maxDisplay = roundToTenth(min(device.maxAvailableVideoZoomFactor / base, 15))
        } else {
            // Front camera: default to the widest field of view when the device offers one.
            let active = device.activeFormat
            let widest = device.formats.max(by: { $0.videoFieldOfView < $1.videoFieldOfView })
            if let widest, widest.videoFieldOfView > active.videoFieldOfView + 1 {
                frontWide = true
                session.sessionPreset = .inputPriority
                if (try? device.lockForConfiguration()) != nil {
                    device.activeFormat = widest
                    device.unlockForConfiguration()
                }
                presets = [1.0, 1.4] // Wide (default) and a tighter crop.
                maxDisplay = roundToTenth(min(device.maxAvailableVideoZoomFactor, 4))
            } else {
                session.sessionPreset = .high
                presets = [1.0]
                maxDisplay = roundToTenth(min(device.maxAvailableVideoZoomFactor, 4))
            }
            minDisplay = 1.0
        }

        // Start at 1x on the new camera.
        applyNativeZoom(base, to: device)

        DispatchQueue.main.async {
            self.baseZoomFactor = base
            self.zoomPresets = presets
            self.minDisplayZoom = minDisplay
            self.maxDisplayZoom = max(maxDisplay, presets.last ?? 1.0)
            self.frontWideSupported = frontWide
            self.displayZoom = 1.0
        }
    }

    /// Sets zoom from a displayed value (e.g. 0.5, 1.0, 2.4). Use `ramp` for smooth
    /// transitions on preset taps; direct application for live pinch updates.
    func setZoom(display: CGFloat, ramp: Bool = false) {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.currentInput?.device else { return }

            let clamped = min(max(display, self.minDisplayZoom), self.maxDisplayZoom)
            let native = clamped * self.baseZoomFactor

            do {
                try device.lockForConfiguration()
                let bounded = min(max(native, device.minAvailableVideoZoomFactor), device.maxAvailableVideoZoomFactor)
                if ramp {
                    device.ramp(toVideoZoomFactor: bounded, withRate: 12)
                } else {
                    device.cancelVideoZoomRamp()
                    device.videoZoomFactor = bounded
                }
                device.unlockForConfiguration()

                DispatchQueue.main.async {
                    self.displayZoom = clamped
                }
            } catch {
                print("setZoom error: \(error.localizedDescription)")
            }
        }
    }

    /// Directly applies a native zoom factor (used to reset on camera changes).
    private func applyNativeZoom(_ factor: CGFloat, to device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = min(max(factor, device.minAvailableVideoZoomFactor), device.maxAvailableVideoZoomFactor)
            device.unlockForConfiguration()
        } catch {
            print("applyNativeZoom error: \(error.localizedDescription)")
        }
    }

    private func roundToTenth(_ value: CGFloat) -> CGFloat {
        (value * 10).rounded() / 10
    }

    private func uniqueSorted(_ values: [CGFloat]) -> [CGFloat] {
        Array(Set(values)).sorted()
    }
}

// MARK: - Photo Capture Delegate

extension CameraManager: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            print("Photo capture error \(error.localizedDescription)")
            return
        }

        guard let imageData = photo.fileDataRepresentation(),
              let uiImage = UIImage(data: imageData) else {
            print("Failed to convert photo to image")
            return
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            let finalImage = self.currentPosition == .front ? (uiImage.mirrored() ?? uiImage) : uiImage
            self.capturedImage = IdentifiableImage(image: finalImage)
        }
    }
}

// MARK: - Video Recording Delegate

extension CameraManager: AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        Task { @MainActor [weak self] in
            self?.isRecording = true
        }
    }

    nonisolated func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        Task { @MainActor [weak self] in
            self?.isRecording = false

            if let error = error {
                print("Video recording error: \(error.localizedDescription)")
                return
            }

            self?.capturedVideoURL = outputFileURL
        }
    }
}

// MARK: - Supporting Types

struct IdentifiableImage: Identifiable, Equatable {
    let id = UUID()
    let image: UIImage

    static func == (lhs: IdentifiableImage, rhs: IdentifiableImage) -> Bool {
        lhs.id == rhs.id
    }
}

extension UIImage {
    func mirrored() -> UIImage? {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            context.cgContext.translateBy(x: size.width, y: 0)
            context.cgContext.scaleBy(x: -1, y: 1)
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
