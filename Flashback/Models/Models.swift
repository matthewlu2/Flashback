//
//  Models.swift
//  Flashback
//
//  Created by Matthew Lu on 1/28/26.
//

import Foundation

struct Profile: Decodable {
  let username: String?
  let fullName: String?
  let website: String?
  enum CodingKeys: String, CodingKey {
    case username
    case fullName = "full_name"
    case website
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
