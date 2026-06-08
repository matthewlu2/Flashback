//
//  AvatarView.swift
//  Flashback
//
//  Created by Claude on 6/7/26.
//

import SwiftUI

/// A circular avatar that shows a remote image when available, otherwise the user's initials.
struct AvatarView: View {
    let urlPath: String?
    let name: String
    var size: CGFloat = 44

    var body: some View {
        Group {
            if let urlPath, let url = URL(string: urlPath), urlPath.hasPrefix("http") {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        initials
                    }
                }
            } else {
                initials
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var initials: some View {
        ZStack {
            Circle().fill(Color.white.opacity(0.15))
            Text(initialsText)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(.white)
        }
    }

    private var initialsText: String {
        let parts = name.split(separator: " ")
        if let first = parts.first?.first {
            if parts.count > 1, let second = parts[1].first {
                return "\(first)\(second)".uppercased()
            }
            return String(first).uppercased()
        }
        return "?"
    }
}
