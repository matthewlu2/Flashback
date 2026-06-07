//
//  ContentView.swift
//  Flashback
//
//  Created by Matthew Lu on 2/22/26.
//

import Foundation
import SwiftUI


struct ContentView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "house")
                }
            CameraView()
                .tabItem {
                    Label("Camera", systemImage: "camera")
                }
            ProfileView()
                .tabItem {
                    Label("Profile", systemImage: "person")
                }
        }
        .task {
            await MediaBackfill.runIfNeeded()
        }
    }
}

#Preview {
    ContentView()
}
