////
////  OldCameraView.swift
////  Flashback
////
////  Created by Matthew Lu on 2/24/26.
////
//
//import SwiftUI
//import UIKit
//import AVFoundation
//import Combine
//
//class CameraManager: NSObject, ObservableObject {
//    @Published var capturedImage: UIImage?
//    @Published var isAuthorized = false
//    @Published var autherizaionStatus: AVAuthorizationStatus = .notDetermined
//
//    let session = AVCaptureSession()
//    private var photoOutput = AVCapturePhotoOutput()
//    private var videoOutput = AVCaptureMovieFileOutput()
//    private var videoDeviceInput: AVCaptureDeviceInput?
//
//    override init() {
//        super.init()
//    }
//
//    func checkPermission() {
//        switch AVCaptureDevice.authorizationStatus(for: .video) {
//        case .authorized:
//            DispatchQueue.main.async {
//                self.isAuthorized = true
//            }
//            setupSession()
//        case .notDetermined:
//            AVCaptureDevice.requestAccess(for: .video) { granted in
//                DispatchQueue.main.async {
//                    self.isAuthorized = granted
//                }
//                if granted {
//                    self.setupSession()
//                }
//            }
//        default:
//            DispatchQueue.main.async {
//                self.isAuthorized = false
//            }
//        }
//    }
//
//    private func setupSession() {
//        session.beginConfiguration()
//        session.sessionPreset = .photo
//
//        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
//              let videoInput = try? AVCaptureDeviceInput(device: videoDevice) else {
//            session.commitConfiguration()
//            return
//        }
//
//        if session.canAddInput(videoInput) {
//            session.addInput(videoInput)
//            videoDeviceInput = videoInput
//        }
//
//        if session.canAddOutput(photoOutput) {
//            session.addOutput(photoOutput)
//        }
//
//        session.commitConfiguration()
//    }
//
//    func startSession() {
//        guard isAuthorized, !session.isRunning else { return }
//        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
//            self?.session.startRunning()
//        }
//    }
//
//    func stopSession() {
//        guard session.isRunning else { return }
//        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
//            self?.session.stopRunning()
//        }
//    }
//
//    func takePhoto() {
//        let settings = AVCapturePhotoSettings()
//        photoOutput.capturePhoto(with: settings, delegate: self)
//    }
//}
//
//extension CameraManager: AVCapturePhotoCaptureDelegate {
//    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
//        guard let imageData = photo.fileDataRepresentation(),
//              let image = UIImage(data: imageData) else { return }
//
//        DispatchQueue.main.async {
//            self.capturedImage = image
//        }
//    }
//}
//
//struct CameraPreview: UIViewRepresentable {
//    let session: AVCaptureSession
//
//    func makeUIView(context: Context) -> UIView {
//        let view = UIView(frame: .zero)
//        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
//        previewLayer.videoGravity = .resizeAspectFill
//        view.layer.addSublayer(previewLayer)
//
//        DispatchQueue.main.async {
//            previewLayer.frame = view.bounds
//        }
//
//        return view
//    }
//
//    func updateUIView(_ uiView: UIView, context: Context) {
//        if let previewLayer = uiView.layer.sublayers?.first as? AVCaptureVideoPreviewLayer {
//            DispatchQueue.main.async {
//                previewLayer.frame = uiView.bounds
//            }
//        }
//    }
//}
//
//struct CameraView: View {
//    @StateObject private var cameraManager = CameraManager()
//
//    var body: some View {
//        ZStack {
//            if cameraManager.isAuthorized {
//                CameraPreview(session: cameraManager.session)
//                    .ignoresSafeArea()
//
//                VStack {
//                    Spacer()
//
//                    Button(action: {
//                        cameraManager.takePhoto()
//                    }) {
//                        Circle()
//                            .fill(Color.white)
//                            .frame(width: 70, height: 70)
//                            .overlay(
//                                Circle()
//                                    .stroke(Color.gray, lineWidth: 3)
//                            )
//                    }
//                    .padding(.bottom, 30)
//                }
//            } else {
//                VStack(spacing: 16) {
//                    Image(systemName: "camera.fill")
//                        .font(.system(size: 50))
//                        .foregroundColor(.gray)
//                    Text("Camera access required")
//                        .font(.headline)
//                    Text("Please enable camera access in Settings")
//                        .font(.subheadline)
//                        .foregroundColor(.gray)
//                }
//            }
//        }
//        .onAppear {
//            cameraManager.checkPermission()
//            cameraManager.startSession()
//        }
//        .onDisappear {
//            cameraManager.stopSession()
//        }
//    }
//}
//
//#Preview {
//    CameraView()
//}
//
