//
//  AvatarCropView.swift
//  Flashback
//
//  Circular crop sheet for profile photos during onboarding.
//

import SwiftUI

struct AvatarCropView: View {
    let image: UIImage
    let onConfirm: (UIImage) -> Void
    let onCancel: () -> Void

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    private let cropDiameter: CGFloat = 280

    var body: some View {
        ZStack {
            AuthBackground()

            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Adjust your photo")
                        .font(.largeTitle.bold())
                        .foregroundStyle(.white)
                    Text("Pinch and drag to position your photo.")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer()

                ZStack {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: cropDiameter, height: cropDiameter)
                        .scaleEffect(scale)
                        .offset(offset)

                    CropOverlay(cropDiameter: cropDiameter)
                        .allowsHitTesting(false)
                }
                .frame(width: cropDiameter, height: cropDiameter)
                .clipShape(Circle())
                .contentShape(Circle())
                .gesture(dragGesture.simultaneously(with: magnificationGesture))

                Spacer()

                VStack(spacing: 16) {
                    AuthPrimaryButton(title: "Use Photo") {
                        if let cropped = MediaProcessor.croppedSquareImage(
                            from: image,
                            scale: scale,
                            offset: offset,
                            cropDiameter: cropDiameter
                        ) {
                            onConfirm(cropped)
                        }
                    }

                    Button("Cancel", action: onCancel)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.gray)
                }
            }
            .padding(.horizontal, 24)
            .safeAreaPadding(.top, 16)
            .safeAreaPadding(.bottom, 16)
        }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                offset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                lastOffset = offset
            }
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = max(1, lastScale * value)
            }
            .onEnded { _ in
                lastScale = scale
            }
    }
}

private struct CropOverlay: View {
    let cropDiameter: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.8), lineWidth: 2)
                .frame(width: cropDiameter, height: cropDiameter)
        }
    }
}
