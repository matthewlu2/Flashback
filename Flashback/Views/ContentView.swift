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

    var body: some View {
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
        .task {
            await MediaBackfill.runIfNeeded()
        }
    }
}

#Preview {
    ContentView()
}
