//
//  ContentView.swift
//  Flashback
//
//  Created by Matthew Lu on 2/22/26.
//

import Foundation
import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 1   // 0 = Home, 1 = Camera, 2 = Profile

    // Edge-swipe tuning
    private let edgeWidth: CGFloat = 20      // how close to the edge the swipe must start
    private let swipeThreshold: CGFloat = 60 // minimum horizontal distance to switch tabs

    var body: some View {
        GeometryReader { proxy in
            TabView(selection: $selectedTab) {
                HomeView()
                    .tabItem {
                        Label("Home", systemImage: "house")
                    }
                    .tag(0)

                CameraView()
                    .tabItem {
                        Label("Camera", systemImage: "camera")
                    }
                    .tag(1)

                ProfileView()
                    .tabItem {
                        Label("Profile", systemImage: "person")
                    }
                    .tag(2)
            }
            .simultaneousGesture(edgeSwipeGesture(width: proxy.size.width))
            .task {
                await MediaBackfill.runIfNeeded()
            }
        }
    }

    private func edgeSwipeGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onEnded { value in
                let dx = value.translation.width
                let dy = value.translation.height
                let startX = value.startLocation.x

                // Reject vertical drags (e.g. list scrolling) and short drags.
                guard abs(dx) > abs(dy), abs(dx) > swipeThreshold else { return }

                // Require the drag to begin near the left or right screen edge.
                let startedAtLeftEdge = startX <= edgeWidth
                let startedAtRightEdge = startX >= width - edgeWidth
                guard startedAtLeftEdge || startedAtRightEdge else { return }

                // Drag right -> previous tab, drag left -> next tab. Clamp to ends.
                let delta = dx > 0 ? -1 : 1
                withAnimation {
                    selectedTab = min(max(selectedTab + delta, 0), 2)
                }
            }
    }
}

#Preview {
    ContentView()
}
