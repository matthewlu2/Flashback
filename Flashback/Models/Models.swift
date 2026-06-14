//
//  Models.swift
//  Flashback
//
//  Created by Matthew Lu on 1/28/26.
//

import Foundation

enum UsernameValidator {
  static let minLength = 3
  static let maxLength = 30
  private static let allowedCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789_.")

  static func normalize(_ raw: String) -> String {
    raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }

  static func validationError(for raw: String) -> String? {
    let normalized = normalize(raw)
    if normalized.count < minLength {
      return "Username must be at least \(minLength) characters."
    }
    if normalized.count > maxLength {
      return "Username must be at most \(maxLength) characters."
    }
    if normalized.unicodeScalars.contains(where: { !allowedCharacters.contains($0) }) {
      return "Use only letters, numbers, underscores, and periods."
    }
    return nil
  }

  static func isDuplicateUsernameError(_ error: Error) -> Bool {
    let message = error.localizedDescription.lowercased()
    return message.contains("duplicate key")
      || message.contains("profiles_username_key")
      || message.contains("unique constraint")
  }
}

enum PhoneValidator {
  private static let allowedCharacters = CharacterSet(charactersIn: "0123456789+()- .")

  static func validationError(for raw: String) -> String? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return nil }

    if trimmed.unicodeScalars.contains(where: { !allowedCharacters.contains($0) }) {
      return "Use only numbers and phone formatting characters (+, spaces, dashes, parentheses)."
    }

    if validatedNormalized(trimmed) == nil {
      return "Please enter a valid phone number."
    }
    return nil
  }

  /// Returns a normalized E.164-style number when the input is valid, otherwise nil.
  static func validatedNormalized(_ raw: String) -> String? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    guard !trimmed.unicodeScalars.contains(where: { !allowedCharacters.contains($0) }) else {
      return nil
    }

    let hasPlus = trimmed.hasPrefix("+")
    let digits = trimmed.filter(\.isNumber)

    if hasPlus {
      guard (8...15).contains(digits.count), digits.first != "0" else { return nil }
      if digits.hasPrefix("1") {
        guard digits.count == 11, isValidNANP(String(digits.dropFirst())) else { return nil }
      }
      return "+" + digits
    }

    if digits.count == 10 {
      guard isValidNANP(digits) else { return nil }
      return "+" + PhoneNormalizer.defaultCountryCode + digits
    }

    if digits.count == 11, digits.hasPrefix(PhoneNormalizer.defaultCountryCode) {
      guard isValidNANP(String(digits.dropFirst())) else { return nil }
      return "+" + digits
    }

    return nil
  }

  static func isDuplicatePhoneError(_ error: Error) -> Bool {
    let message = error.localizedDescription.lowercased()
    return message.contains("duplicate key")
      || message.contains("profiles_phone_normalized_key")
      || message.contains("unique constraint")
  }

  private static func isValidNANP(_ tenDigits: String) -> Bool {
    guard tenDigits.count == 10, tenDigits.allSatisfy(\.isNumber) else { return false }
    let digits = Array(tenDigits)
    return digits[0] >= "2" && digits[0] <= "9"
      && digits[3] >= "2" && digits[3] <= "9"
  }
}

struct Profile: Decodable {
  let id: UUID?
  let username: String?
  let fullName: String?
  let website: String?
  let avatarUrl: String?
  let phone: String?
  let onboardingCompleted: Bool?
  enum CodingKeys: String, CodingKey {
    case id
    case username
    case fullName = "full_name"
    case website
    case avatarUrl = "avatar_url"
    case phone
    case onboardingCompleted = "onboarding_completed"
  }

  var displayName: String {
    if let username, !username.isEmpty { return username }
    if let fullName, !fullName.isEmpty { return fullName }
    return "Unknown"
  }
}
struct UpdateProfileParams: Encodable {
  let username: String
  let fullName: String
  let website: String
  enum CodingKeys: String, CodingKey {
    case username
    case fullName = "full_name"
    case website
  }
}

// MARK: - Flashback Models

struct Flashback: Codable, Identifiable {
  let id: UUID
  let userId: UUID
  let name: String
  let coverImagePath: String?
  let coverThumbnailPath: String?
  let createdAt: Date
  let updatedAt: Date

  enum CodingKeys: String, CodingKey {
    case id
    case userId = "user_id"
    case name
    case coverImagePath = "cover_image_path"
    case coverThumbnailPath = "cover_thumbnail_path"
    case createdAt = "created_at"
    case updatedAt = "updated_at"
  }
}

struct CreateFlashbackParams: Encodable {
  let userId: UUID
  let name: String

  enum CodingKeys: String, CodingKey {
    case userId = "user_id"
    case name
  }
}

enum MediaType: String, Codable {
  case photo
  case video
}

struct FlashbackPhoto: Codable, Identifiable {
  let id: UUID
  let flashbackId: UUID
  let storagePath: String
  let thumbnailPath: String?
  let mediaType: MediaType
  let durationSeconds: Float?
  let createdAt: Date

  enum CodingKeys: String, CodingKey {
    case id
    case flashbackId = "flashback_id"
    case storagePath = "storage_path"
    case thumbnailPath = "thumbnail_path"
    case mediaType = "media_type"
    case durationSeconds = "duration_seconds"
    case createdAt = "created_at"
  }
}

struct CreateFlashbackPhotoParams: Encodable {
  let flashbackId: UUID
  let storagePath: String
  let thumbnailPath: String?
  let mediaType: MediaType
  let durationSeconds: Float?

  enum CodingKeys: String, CodingKey {
    case flashbackId = "flashback_id"
    case storagePath = "storage_path"
    case thumbnailPath = "thumbnail_path"
    case mediaType = "media_type"
    case durationSeconds = "duration_seconds"
  }
}

// MARK: - Social Models

/// A lightweight, shareable public view of another user (returned by friend discovery / member lookups).
struct PublicProfile: Codable, Identifiable, Hashable {
  let id: UUID
  let username: String?
  let fullName: String?
  let avatarUrl: String?

  enum CodingKeys: String, CodingKey {
    case id
    case username
    case fullName = "full_name"
    case avatarUrl = "avatar_url"
  }

  var displayName: String {
    if let username, !username.isEmpty { return username }
    if let fullName, !fullName.isEmpty { return fullName }
    return "Unknown"
  }
}

enum FriendshipStatus: String, Codable {
  case pending
  case accepted
}

struct Friendship: Codable, Identifiable {
  let id: UUID
  let requesterId: UUID
  let addresseeId: UUID
  let status: FriendshipStatus
  let createdAt: Date

  enum CodingKeys: String, CodingKey {
    case id
    case requesterId = "requester_id"
    case addresseeId = "addressee_id"
    case status
    case createdAt = "created_at"
  }
}

struct CreateFriendshipParams: Encodable {
  let requesterId: UUID
  let addresseeId: UUID

  enum CodingKeys: String, CodingKey {
    case requesterId = "requester_id"
    case addresseeId = "addressee_id"
  }
}

enum MemberRole: String, Codable {
  case owner
  case member
}

struct FlashbackMember: Codable, Identifiable {
  let id: UUID
  let flashbackId: UUID
  let userId: UUID
  let role: MemberRole
  let createdAt: Date

  enum CodingKeys: String, CodingKey {
    case id
    case flashbackId = "flashback_id"
    case userId = "user_id"
    case role
    case createdAt = "created_at"
  }
}

struct FlashbackInvite: Codable, Identifiable {
  let id: UUID
  let flashbackId: UUID
  let token: String
  let createdBy: UUID
  let expiresAt: Date?
  let createdAt: Date

  enum CodingKeys: String, CodingKey {
    case id
    case flashbackId = "flashback_id"
    case token
    case createdBy = "created_by"
    case expiresAt = "expires_at"
    case createdAt = "created_at"
  }
}

struct CreateInviteParams: Encodable {
  let flashbackId: UUID
  let token: String
  let createdBy: UUID

  enum CodingKeys: String, CodingKey {
    case flashbackId = "flashback_id"
    case token
    case createdBy = "created_by"
  }
}

enum JoinRequestStatus: String, Codable {
  case pending
  case approved
  case denied
}

struct FlashbackJoinRequest: Codable, Identifiable {
  let id: UUID
  let flashbackId: UUID
  let userId: UUID
  let status: JoinRequestStatus
  let createdAt: Date

  enum CodingKeys: String, CodingKey {
    case id
    case flashbackId = "flashback_id"
    case userId = "user_id"
    case status
    case createdAt = "created_at"
  }
}
