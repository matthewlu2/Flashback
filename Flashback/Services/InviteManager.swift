//
//  InviteManager.swift
//  Flashback
//
//  Created by Claude on 6/7/26.
//

import SwiftUI
import CoreImage.CIFilterBuiltins
import Supabase
import Combine

@MainActor
class InviteManager: ObservableObject {
    static let shared = InviteManager()

    /// A join token captured from a deep link before the user is authenticated/onboarded.
    @Published var pendingToken: String?
    /// User-facing message shown after a join attempt resolves.
    @Published var joinMessage: String?

    private let context = CIContext()
    private let qrFilter = CIFilter.qrCodeGenerator()

    private init() {}

    // MARK: - Deep links

    /// Parses `flashback://join?token=...` and stashes the token for processing once authenticated.
    func handle(url: URL) {
        guard url.scheme == "flashback" else { return }
        guard url.host == "join" || url.path.contains("join") else { return }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if let token = components?.queryItems?.first(where: { $0.name == "token" })?.value, !token.isEmpty {
            pendingToken = token
        }
    }

    func processPendingJoinIfNeeded() async {
        guard let token = pendingToken else { return }
        pendingToken = nil
        await submitJoinRequest(token: token)
    }

    /// Sends a join request for an invite token and surfaces the result. Returns true if it joined or requested.
    @discardableResult
    func submitJoinRequest(token: String) async -> Bool {
        do {
            try await supabase
                .rpc("request_join", params: ["invite_token": token])
                .execute()

            // The owner must approve before the album appears, so refresh in case it was auto-resolved.
            FlashbackManager.shared.refresh()
            joinMessage = "Your request to join was sent. You'll get access once the owner approves."
            return true
        } catch {
            print("request_join error: \(error.localizedDescription)")
            joinMessage = "This invite is invalid or has expired."
            return false
        }
    }

    // MARK: - Creating invites

    /// Creates (or reuses logic is left simple: always creates) an invite token for a flashback.
    func createInvite(for flashbackId: UUID) async throws -> FlashbackInvite {
        let me = try await supabase.auth.session.user.id
        let token = Self.generateToken()

        let params = CreateInviteParams(flashbackId: flashbackId, token: token, createdBy: me)
        let invite: FlashbackInvite = try await supabase
            .from("flashback_invites")
            .insert(params)
            .select()
            .single()
            .execute()
            .value
        return invite
    }

    /// Returns the most recent existing invite for a flashback, if any.
    func existingInvite(for flashbackId: UUID) async throws -> FlashbackInvite? {
        let invites: [FlashbackInvite] = try await supabase
            .from("flashback_invites")
            .select()
            .eq("flashback_id", value: flashbackId)
            .order("created_at", ascending: false)
            .limit(1)
            .execute()
            .value
        return invites.first
    }

    /// Returns an existing invite or creates a new one.
    func inviteOrCreate(for flashbackId: UUID) async throws -> FlashbackInvite {
        if let existing = try await existingInvite(for: flashbackId) {
            return existing
        }
        return try await createInvite(for: flashbackId)
    }

    private static func generateToken() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    // MARK: - URL & QR

    func inviteURL(token: String) -> URL {
        URL(string: "flashback://join?token=\(token)")!
    }

    func qrImage(for string: String) -> UIImage? {
        let data = Data(string.utf8)
        qrFilter.setValue(data, forKey: "inputMessage")
        qrFilter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = qrFilter.outputImage else { return nil }

        // Scale up so the QR is crisp.
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    /// Renders the QR off the main thread so presenting the share sheet never blocks the UI.
    nonisolated static func makeQRCode(from string: String) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            let filter = CIFilter.qrCodeGenerator()
            filter.setValue(Data(string.utf8), forKey: "inputMessage")
            filter.setValue("M", forKey: "inputCorrectionLevel")
            guard let output = filter.outputImage else { return nil }

            let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
            let context = CIContext()
            guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
            return UIImage(cgImage: cgImage)
        }.value
    }
}
