//
//  Models.swift
//  Flashback
//
//  Created by Matthew Lu on 1/28/26.
//

import Foundation

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
