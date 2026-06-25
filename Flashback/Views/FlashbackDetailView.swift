//
//  FlashbackDetailView.swift
//  Flashback
//
//  Created by Claude on 4/14/26.
//

import SwiftUI
import AVKit
import PhotosUI

struct FlashbackDetailView: View {
    let flashback: Flashback

    @ObservedObject private var flashbackManager = FlashbackManager.shared
    @State private var media: [FlashbackPhoto] = []
    @State private var isLoading = true
    @State private var mediaToDelete: FlashbackPhoto?
    @State private var showingDeleteConfirmation = false
    @State private var selectedMedia: FlashbackPhoto?
    @State private var showingShare = false
    @State private var showingCoverPicker = false
    @State private var isOwner = false

    // Current user (for media ownership checks) & multi-select state.
    @State private var currentUserId: UUID?
    @State private var isSelecting = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var showingNotYoursAlert = false
    @State private var showingBulkDeleteConfirm = false
    @State private var saveResultMessage: String?
    @State private var isSaving = false

    // Sorting & filtering state (per-view, not persisted).
    @State private var sortField: MediaSortField = .takenAt
    @State private var sortAscending = false
    @State private var filterUploaderIds: Set<UUID> = []
    @State private var mediaTypeFilter: MediaTypeFilter = .all
    @State private var members: [MemberInfo] = []

    private let columns = [
        GridItem(.flexible(), spacing: 1),
        GridItem(.flexible(), spacing: 1),
        GridItem(.flexible(), spacing: 1)
    ]

    /// The album, reflecting any cover change made through the shared manager.
    private var currentFlashback: Flashback {
        flashbackManager.flashbacks.first { $0.id == flashback.id } ?? flashback
    }

    /// Media after applying the active filters and sort order.
    private var displayedMedia: [FlashbackPhoto] {
        var result = media.filter { mediaTypeFilter.matches($0) }
        if !filterUploaderIds.isEmpty {
            result = result.filter { item in
                guard let uploader = item.uploadedBy else { return false }
                return filterUploaderIds.contains(uploader)
            }
        }
        return result.sorted { a, b in
            return sortAscending ? a.effectiveTakenAt < b.effectiveTakenAt
                                 : a.effectiveTakenAt > b.effectiveTakenAt
        }
    }

    /// True when the current user may delete this media: they uploaded it, or they
    /// own the album (matches the uploader-or-owner RLS policy).
    private func canDelete(_ item: FlashbackPhoto) -> Bool {
        isOwner || (item.uploadedBy != nil && item.uploadedBy == currentUserId)
    }

    /// The currently selected media items, in displayed order.
    private var selectedItems: [FlashbackPhoto] {
        displayedMedia.filter { selectedIDs.contains($0.id) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                coverHeader

                if !media.isEmpty {
                    controlsBar
                }

                if isLoading {
                    ProgressView()
                        .padding(.top, 50)
                } else if media.isEmpty {
                    Text("No photos or videos in this flashback")
                        .foregroundColor(.gray)
                        .padding(.top, 50)
                } else if displayedMedia.isEmpty {
                    Text("No media matches the current filters")
                        .foregroundColor(.gray)
                        .padding(.top, 50)
                } else {
                    LazyVGrid(columns: columns, spacing: 1) {
                        ForEach(displayedMedia) { item in
                            MediaGridItem(media: item, isSelecting: isSelecting, isSelected: selectedIDs.contains(item.id))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if isSelecting {
                                        toggleSelection(item)
                                    } else {
                                        selectedMedia = item
                                    }
                                }
                                .contextMenu {
                                    if !isSelecting {
                                        Button {
                                            saveSingle(item)
                                        } label: {
                                            Label("Save to Photos", systemImage: "square.and.arrow.down")
                                        }
                                        if isOwner {
                                            Button {
                                                setCover(to: item)
                                            } label: {
                                                Label("Set as Cover", systemImage: "photo")
                                            }
                                        }
                                        if canDelete(item) {
                                            Button(role: .destructive) {
                                                mediaToDelete = item
                                                showingDeleteConfirmation = true
                                            } label: {
                                                Label("Delete", systemImage: "trash")
                                            }
                                        }
                                    }
                                }
                        }
                    }
                }
            }
        }
        .refreshable {
            await loadMedia()
        }
        .navigationTitle(currentFlashback.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isSelecting {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        exitSelection()
                    }
                }
            } else {
                if !media.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Select") {
                            isSelecting = true
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingShare = true
                    } label: {
                        Image(systemName: "person.crop.circle.badge.plus")
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if isSelecting {
                selectionActionBar
            }
        }
        .sheet(isPresented: $showingShare) {
            ShareFlashbackView(flashback: flashback, isOwner: isOwner)
        }
        .sheet(isPresented: $showingCoverPicker) {
            CoverPickerView(flashback: flashback, media: media)
        }
        .alert("Delete", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                mediaToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let item = mediaToDelete {
                    deleteMedia(item)
                }
            }
        } message: {
            Text("Are you sure you want to delete this? This cannot be undone.")
        }
        .alert("Can't Delete", isPresented: $showingNotYoursAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Some selected photos aren't yours, so they can't be deleted.")
        }
        .alert("Delete \(selectedIDs.count) Items", isPresented: $showingBulkDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deleteSelected()
            }
        } message: {
            Text("Are you sure you want to delete these? This cannot be undone.")
        }
        .alert("Save to Photos", isPresented: .init(
            get: { saveResultMessage != nil },
            set: { if !$0 { saveResultMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveResultMessage ?? "")
        }
        .fullScreenCover(item: $selectedMedia) { item in
            MediaFullScreenView(
                media: item,
                canDelete: canDelete(item),
                onDismiss: { selectedMedia = nil },
                onDelete: { media in
                    deleteMedia(media)
                    selectedMedia = nil
                }
            )
        }
        .overlay {
            if isSaving {
                ProgressView().tint(.white)
                    .padding(24)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .task {
            // Resolve ownership first (it's a fast local-session check) so the share sheet
            // and owner-only controls reflect the correct state immediately.
            isOwner = await FlashbackManager.shared.isOwner(of: flashback)
            currentUserId = await FlashbackManager.shared.currentUserId()
            await loadMedia()
            await loadMembers()
        }
        .onReceive(flashbackManager.$lastMediaUpdate) { update in
            // A photo/video finished uploading to an album. Reload if it's this one.
            guard let update, update.flashbackId == flashback.id else { return }
            Task { await loadMedia() }
        }
    }

    // MARK: - Cover header

    @ViewBuilder
    private var coverHeader: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let coverPath = currentFlashback.coverImagePath ?? currentFlashback.coverThumbnailPath {
                    CachedAsyncImage(storagePath: coverPath, contentMode: .fill)
                } else {
                    Color.gray.opacity(0.2)
                        .overlay {
                            VStack(spacing: 8) {
                                Image(systemName: "photo.on.rectangle.angled")
                                    .font(.system(size: 36))
                                Text(isOwner ? "Tap to set a cover" : "No cover yet")
                                    .font(.subheadline)
                            }
                            .foregroundColor(.gray)
                        }
                }
            }
            .frame(height: 300)
            .frame(maxWidth: .infinity)
            .clipped()

            // Darkening gradient so the title stays legible over any image.
            LinearGradient(
                colors: [.clear, .black.opacity(0.55)],
                startPoint: .center,
                endPoint: .bottom
            )
            .frame(height: 300)
            .allowsHitTesting(false)

            HStack(alignment: .bottom) {
                Text(currentFlashback.name)
                    .font(.largeTitle.bold())
                    .foregroundColor(.white)
                    .shadow(radius: 4)

                Spacer()

                if isOwner {
                    Button {
                        showingCoverPicker = true
                    } label: {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(10)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                }
            }
            .padding(16)
        }
        .frame(height: 300)
        .contentShape(Rectangle())
        .onTapGesture {
            if isOwner { showingCoverPicker = true }
        }
    }

    // MARK: - Sort / filter controls

    private var controlsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                // Sort
                Menu {
                    Picker("Sort by", selection: $sortField) {
                        ForEach(MediaSortField.allCases) { field in
                            Text(field.title).tag(field)
                        }
                    }
                    Divider()
                    Picker("Order", selection: $sortAscending) {
                        Text("Newest first").tag(false)
                        Text("Oldest first").tag(true)
                    }
                } label: {
                    controlChip(
                        systemImage: "arrow.up.arrow.down",
                        text: "\(sortField.title) · \(sortAscending ? "Oldest" : "Newest")",
                        active: false
                    )
                }

                // Filter by uploader
                Menu {
                    Button {
                        filterUploaderIds.removeAll()
                    } label: {
                        Label("Everyone", systemImage: filterUploaderIds.isEmpty ? "checkmark" : "")
                    }
                    Divider()
                    ForEach(members) { member in
                        Button {
                            toggleUploader(member.userId)
                        } label: {
                            Label(
                                member.displayName,
                                systemImage: filterUploaderIds.contains(member.userId) ? "checkmark" : ""
                            )
                        }
                    }
                } label: {
                    controlChip(
                        systemImage: "person.2",
                        text: uploaderFilterLabel,
                        active: !filterUploaderIds.isEmpty
                    )
                }

                // Filter by media type
                Menu {
                    Picker("Show", selection: $mediaTypeFilter) {
                        ForEach(MediaTypeFilter.allCases) { type in
                            Text(type.title).tag(type)
                        }
                    }
                } label: {
                    controlChip(
                        systemImage: "square.grid.2x2",
                        text: mediaTypeFilter.title,
                        active: mediaTypeFilter != .all
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }

    private func controlChip(systemImage: String, text: String, active: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
            Text(text)
        }
        .font(.subheadline.weight(.medium))
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(active ? Color.blue.opacity(0.15) : Color(.systemGray6))
        .foregroundColor(active ? .blue : .primary)
        .clipShape(Capsule())
    }

    private var uploaderFilterLabel: String {
        if filterUploaderIds.isEmpty { return "Everyone" }
        if filterUploaderIds.count == 1,
           let id = filterUploaderIds.first,
           let member = members.first(where: { $0.userId == id }) {
            return member.displayName
        }
        return "\(filterUploaderIds.count) people"
    }

    private func toggleUploader(_ id: UUID) {
        if filterUploaderIds.contains(id) {
            filterUploaderIds.remove(id)
        } else {
            filterUploaderIds.insert(id)
        }
    }

    // MARK: - Selection action bar

    private var selectionActionBar: some View {
        HStack(spacing: 12) {
            Button {
                saveSelected()
            } label: {
                Label("Save (\(selectedIDs.count))", systemImage: "square.and.arrow.down")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(selectedIDs.isEmpty)

            Button {
                attemptBulkDelete()
            } label: {
                Label("Delete (\(selectedIDs.count))", systemImage: "trash")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundColor(.red)
                    .background(Color.red.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(selectedIDs.isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    // MARK: - Selection actions

    private func toggleSelection(_ item: FlashbackPhoto) {
        if selectedIDs.contains(item.id) {
            selectedIDs.remove(item.id)
        } else {
            selectedIDs.insert(item.id)
        }
    }

    private func exitSelection() {
        isSelecting = false
        selectedIDs.removeAll()
    }

    private func attemptBulkDelete() {
        // Block the entire delete if any selected item can't be deleted by this user
        // (i.e. they're not the uploader and don't own the album).
        if selectedItems.contains(where: { !canDelete($0) }) {
            showingNotYoursAlert = true
        } else {
            showingBulkDeleteConfirm = true
        }
    }

    private func saveSingle(_ item: FlashbackPhoto) {
        Task {
            isSaving = true
            defer { isSaving = false }
            do {
                try await PhotoLibrarySaver.save(item)
                saveResultMessage = "Saved to your camera roll."
            } catch {
                saveResultMessage = error.localizedDescription
            }
        }
    }

    private func saveSelected() {
        let items = selectedItems
        guard !items.isEmpty else { return }
        Task {
            isSaving = true
            defer { isSaving = false }
            let result = await PhotoLibrarySaver.saveAll(items)
            if result.failed == 0 {
                saveResultMessage = "Saved \(result.saved) item\(result.saved == 1 ? "" : "s") to your camera roll."
            } else if result.saved == 0 {
                saveResultMessage = "Couldn't save \(result.failed) item\(result.failed == 1 ? "" : "s"). Check photo library permissions in Settings."
            } else {
                saveResultMessage = "Saved \(result.saved); \(result.failed) couldn't be saved."
            }
            exitSelection()
        }
    }

    private func deleteSelected() {
        let items = selectedItems
        Task {
            for item in items {
                do {
                    try await FlashbackManager.shared.deletePhoto(item, isAlbumOwner: isOwner)
                    media.removeAll { $0.id == item.id }
                } catch {
                    print("Failed to delete: \(error.localizedDescription)")
                }
            }
            exitSelection()
        }
    }

    // MARK: - Data

    private func deleteMedia(_ item: FlashbackPhoto) {
        Task {
            do {
                try await FlashbackManager.shared.deletePhoto(item, isAlbumOwner: isOwner)
                media.removeAll { $0.id == item.id }
            } catch {
                print("Failed to delete: \(error.localizedDescription)")
            }
            mediaToDelete = nil
        }
    }

    private func setCover(to item: FlashbackPhoto) {
        Task {
            do {
                try await FlashbackManager.shared.setCover(
                    for: flashback.id,
                    imagePath: item.storagePath,
                    thumbnailPath: item.thumbnailPath
                )
            } catch {
                print("Failed to set cover: \(error.localizedDescription)")
            }
        }
    }

    private func loadMedia() async {
        // Only show the full-screen spinner on the first load; background reloads (after an
        // upload or pull-to-refresh) should update the grid in place without flashing.
        if media.isEmpty {
            isLoading = true
        }
        defer { isLoading = false }

        do {
            media = try await FlashbackManager.shared.loadPhotos(for: flashback.id)
        } catch {
            print("Failed to load media: \(error.localizedDescription)")
        }
    }

    private func loadMembers() async {
        do {
            members = try await FlashbackManager.shared.members(for: flashback.id)
        } catch {
            print("Failed to load members: \(error.localizedDescription)")
        }
    }
}

// MARK: - Cover Picker

private struct CoverPickerView: View {
    let flashback: Flashback
    let media: [FlashbackPhoto]

    @Environment(\.dismiss) private var dismiss
    @State private var pickerItem: PhotosPickerItem?
    @State private var isUploading = false

    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label("Choose from Camera Roll", systemImage: "photo.badge.plus")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding()

                if !media.isEmpty {
                    HStack {
                        Text("Or pick from this album")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal)

                    LazyVGrid(columns: columns, spacing: 2) {
                        ForEach(media) { item in
                            CachedAsyncImage(storagePath: item.thumbnailPath ?? item.storagePath, contentMode: .fill)
                                .aspectRatio(1, contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    chooseExisting(item)
                                }
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }
            .overlay {
                if isUploading {
                    ProgressView().tint(.white)
                        .padding(24)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .navigationTitle("Set Cover")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                uploadFromLibrary(item)
            }
        }
    }

    private func chooseExisting(_ item: FlashbackPhoto) {
        Task {
            do {
                try await FlashbackManager.shared.setCover(
                    for: flashback.id,
                    imagePath: item.storagePath,
                    thumbnailPath: item.thumbnailPath
                )
                dismiss()
            } catch {
                print("Failed to set cover: \(error.localizedDescription)")
            }
        }
    }

    private func uploadFromLibrary(_ item: PhotosPickerItem) {
        isUploading = true
        Task {
            defer { isUploading = false }
            do {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else { return }
                try await FlashbackManager.shared.uploadCover(image, for: flashback.id)
                dismiss()
            } catch {
                print("Failed to upload cover: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Grid Item

private struct MediaGridItem: View {
    let media: FlashbackPhoto
    var isSelecting: Bool = false
    var isSelected: Bool = false

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)   // forces a square footprint
            .overlay {
                gridContent
            }
            .clipped()
    }

    private var gridContent: some View {
        ZStack {
            CachedAsyncImage(storagePath: media.thumbnailPath ?? media.storagePath, contentMode: .fill)

            if media.mediaType == .video {
                VStack {
                    Spacer()
                    HStack {
                        Image(systemName: "video.fill")
                            .font(.system(size: 12))
                        if let duration = media.durationSeconds {
                            Text(formatDuration(duration))
                                .font(.caption2)
                        }
                        Spacer()
                    }
                    .foregroundColor(.white)
                    .padding(6)
                    .background(
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.6)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
            }

            if isSelecting {
                Color.black.opacity(isSelected ? 0.25 : 0.0)
                VStack {
                    HStack {
                        Spacer()
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 22))
                            .foregroundColor(isSelected ? .blue : .white)
                            .background(Circle().fill(.white.opacity(isSelected ? 1 : 0.3)).padding(2))
                            .padding(6)
                    }
                    Spacer()
                }
            }
        }
    }

    private func formatDuration(_ seconds: Float) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Full Screen View

struct MediaFullScreenView: View {
    let media: FlashbackPhoto
    let canDelete: Bool
    let onDismiss: () -> Void
    let onDelete: (FlashbackPhoto) -> Void

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var showingDeleteConfirmation = false
    @State private var player: AVPlayer?
    @State private var photo: UIImage?
    @State private var isSaving = false
    @State private var saveResultMessage: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if media.mediaType == .video {
                VideoPlayer(player: player)
                    .task {
                        if let url = try? await FlashbackManager.shared.getSignedURL(for: media.storagePath) {
                            player = AVPlayer(url: url)
                            player?.play()
                        }
                    }
                    .onDisappear {
                        player?.pause()
                        player = nil
                    }
            } else {
                if let photo {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(scale)
                        .gesture(
                            MagnifyGesture()
                                .onChanged { value in
                                    scale = lastScale * value.magnification
                                }
                                .onEnded { _ in
                                    lastScale = scale
                                    if scale < 1.0 {
                                        withAnimation {
                                            scale = 1.0
                                            lastScale = 1.0
                                        }
                                    }
                                }
                        )
                        .onTapGesture(count: 2) {
                            withAnimation {
                                if scale > 1.0 {
                                    scale = 1.0
                                    lastScale = 1.0
                                } else {
                                    scale = 2.0
                                    lastScale = 2.0
                                }
                            }
                        }
                } else {
                    ProgressView()
                        .tint(.white)
                        .task {
                            photo = await MediaCache.shared.image(forStoragePath: media.storagePath)
                        }
                }
            }

            // Top bar
            VStack {
                HStack(spacing: 12) {
                    if canDelete {
                        Button {
                            showingDeleteConfirmation = true
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.white)
                                .padding(12)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                        }
                    }

                    Button {
                        save()
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.white)
                            .padding(12)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                    .disabled(isSaving)

                    Spacer()

                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(.white)
                            .padding(12)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 60)
                Spacer()
            }

            if isSaving {
                ProgressView().tint(.white)
                    .padding(24)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .alert("Delete", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                onDelete(media)
            }
        } message: {
            Text("Are you sure you want to delete this? This cannot be undone.")
        }
        .alert("Save to Photos", isPresented: .init(
            get: { saveResultMessage != nil },
            set: { if !$0 { saveResultMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveResultMessage ?? "")
        }
    }

    private func save() {
        Task {
            isSaving = true
            defer { isSaving = false }
            do {
                try await PhotoLibrarySaver.save(media)
                saveResultMessage = "Saved to your camera roll."
            } catch {
                saveResultMessage = error.localizedDescription
            }
        }
    }
}
