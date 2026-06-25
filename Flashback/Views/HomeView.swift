//
//  HomeView.swift
//  Flashback
//
//  Created by Matthew Lu on 2/22/26.
//

import SwiftUI

struct HomeView: View {
    @StateObject private var flashbackManager = FlashbackManager.shared
    @State private var showingCreate = false

    var body: some View {
        NavigationStack {
            Group {
                if flashbackManager.flashbacks.isEmpty && !flashbackManager.isLoading {
                    emptyState
                } else {
                    List {
                        ForEach(flashbackManager.flashbacks) { flashback in
                            NavigationLink(destination: FlashbackDetailView(flashback: flashback)) {
                                FlashbackRowView(flashback: flashback, isSelected: false)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Flashbacks")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingCreate = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingCreate) {
                CreateAlbumView { _ in }
            }
            .task {
                await flashbackManager.loadFlashbacksIfNeeded()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 48))
                .foregroundColor(.gray)
            Text("No albums yet")
                .font(.headline)
            Text("Create a flashback to start capturing moments with friends.")
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button {
                showingCreate = true
            } label: {
                Label("Create Album", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 20).padding(.vertical, 10)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .clipShape(Capsule())
            }
        }
    }
}

#Preview {
    HomeView()
}
