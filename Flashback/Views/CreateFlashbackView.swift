//
//  CreateFlashbackView.swift
//  Flashback
//
//  Created by Claude on 4/14/26.
//

import SwiftUI

struct CreateFlashbackView: View {
    let onCreated: (Flashback) -> Void

    @State private var name = ""
    @State private var isCreating = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Flashback Name", text: $name)
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("New Flashback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createFlashback()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isCreating)
                }
            }
        }
    }

    private func createFlashback() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        isCreating = true
        errorMessage = nil

        Task {
            do {
                let flashback = try await FlashbackManager.shared.createFlashback(name: trimmedName)
                dismiss()
                onCreated(flashback)
            } catch {
                errorMessage = "Failed to create flashback: \(error.localizedDescription)"
                isCreating = false
            }
        }
    }
}
