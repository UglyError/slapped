import Foundation
import CoreLocation

struct StickerCard: Codable, Identifiable, Hashable {
    let id: UUID
    let name: String
    let details: String?
    let imageUrl: String
    let lat: Double
    let lng: Double
    let placeName: String?
    let likeCount: Int
    let tradeCount: Int
    let value: Int
    let createdAt: Date
    let finderId: UUID
    let finderUsername: String
    let finderAvatarUrl: String?
    let ownerId: UUID
    let ownerUsername: String
    let ownerAvatarUrl: String?
    let likedByMe: Bool
    let commentCount: Int?
    let series: String?

    enum CodingKeys: String, CodingKey {
        case id, name, lat, lng, value
        case details = "description"
        case imageUrl = "image_url"
        case placeName = "place_name"
        case likeCount = "like_count"
        case tradeCount = "trade_count"
        case createdAt = "created_at"
        case finderId = "finder_id"
        case finderUsername = "finder_username"
        case finderAvatarUrl = "finder_avatar_url"
        case ownerId = "owner_id"
        case ownerUsername = "owner_username"
        case ownerAvatarUrl = "owner_avatar_url"
        case likedByMe = "liked_by_me"
        case commentCount = "comment_count"
        case series
    }

    var coordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lng) }
    var imageURL: URL? { URL(string: imageUrl) }
    var wasTraded: Bool { ownerId != finderId }
}

struct ProfileStats: Codable, Identifiable, Hashable {
    let id: UUID
    let username: String
    let displayName: String?
    let avatarUrl: String?
    let bio: String?
    let createdAt: Date
    let finds: Int
    let owned: Int
    let collectionValue: Int
    let followers: Int
    let following: Int
    let followedByMe: Bool
    let blockedByMe: Bool?

    enum CodingKeys: String, CodingKey {
        case id, username, bio, finds, owned, followers, following
        case displayName = "display_name"
        case avatarUrl = "avatar_url"
        case createdAt = "created_at"
        case collectionValue = "collection_value"
        case followedByMe = "followed_by_me"
        case blockedByMe = "blocked_by_me"
    }

    var titleName: String { displayName?.isEmpty == false ? displayName! : username }
}

struct MiniProfile: Codable, Hashable, Identifiable {
    let id: UUID
    let username: String
    let avatarUrl: String?

    enum CodingKeys: String, CodingKey {
        case id, username
        case avatarUrl = "avatar_url"
    }
}

struct MiniSticker: Codable, Hashable, Identifiable {
    let id: UUID
    let name: String
    let imageUrl: String
    let value: Int

    enum CodingKeys: String, CodingKey {
        case id, name, value
        case imageUrl = "image_url"
    }

    var imageURL: URL? { URL(string: imageUrl) }
}

enum TradeStatus: String, Codable {
    case pending, accepted, declined, cancelled
}

struct Trade: Codable, Identifiable, Hashable {
    let id: UUID
    let proposerId: UUID
    let recipientId: UUID
    let status: TradeStatus
    let message: String?
    let createdAt: Date
    let proposer: MiniProfile
    let recipient: MiniProfile
    let tradeItems: [TradeItem]

    enum CodingKeys: String, CodingKey {
        case id, status, message, proposer, recipient
        case proposerId = "proposer_id"
        case recipientId = "recipient_id"
        case createdAt = "created_at"
        case tradeItems = "trade_items"
    }

    /// Stickers the proposer gives up.
    var offered: [MiniSticker] { tradeItems.filter { $0.side == "offer" }.map(\.sticker) }
    /// Stickers the proposer wants.
    var requested: [MiniSticker] { tradeItems.filter { $0.side == "request" }.map(\.sticker) }
}

struct TradeItem: Codable, Hashable {
    let side: String
    let sticker: MiniSticker
}

struct Transfer: Codable, Identifiable, Hashable {
    let id: UUID
    let createdAt: Date
    let fromUser: MiniProfile
    let toUser: MiniProfile

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case fromUser = "from_user"
        case toUser = "to_user"
    }
}

struct CommentCard: Codable, Identifiable, Hashable {
    let id: UUID
    let stickerId: UUID
    let body: String
    let createdAt: Date
    let userId: UUID
    let username: String
    let avatarUrl: String?

    enum CodingKeys: String, CodingKey {
        case id, body, username
        case stickerId = "sticker_id"
        case createdAt = "created_at"
        case userId = "user_id"
        case avatarUrl = "avatar_url"
    }
}

struct ActivityItem: Codable, Identifiable, Hashable {
    let kind: String
    let actorId: UUID
    let actorUsername: String
    let actorAvatarUrl: String?
    let stickerId: UUID?
    let stickerName: String?
    let stickerImageUrl: String?
    let body: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case kind, body
        case actorId = "actor_id"
        case actorUsername = "actor_username"
        case actorAvatarUrl = "actor_avatar_url"
        case stickerId = "sticker_id"
        case stickerName = "sticker_name"
        case stickerImageUrl = "sticker_image_url"
        case createdAt = "created_at"
    }

    var id: String { "\(kind)-\(actorId)-\(stickerId?.uuidString ?? "")-\(createdAt.timeIntervalSince1970)" }
}

struct Badge: Codable, Identifiable, Hashable {
    let code: String
    let title: String
    let detail: String
    let icon: String
    var tier: String?
    var progress: Int?
    var target: Int?
    var earned: Bool?

    var id: String { code }
    var isEarned: Bool { earned ?? true }
    var fraction: Double {
        guard let progress, let target, target > 0 else { return isEarned ? 1 : 0 }
        return min(1, Double(progress) / Double(target))
    }
}

struct BlockedUser: Codable, Identifiable, Hashable {
    let blocked: MiniProfile

    var id: UUID { blocked.id }
}

enum Route: Hashable {
    case sticker(StickerCard)
    case stickerID(UUID)
    case profile(UUID)
    case trades
    case activity
    case settings
    case blockedUsers
    case badges(UUID)
    case series(String)
}

struct SeriesSummary: Codable, Identifiable, Hashable {
    let series: String
    let total: Int
    let owned: Int
    let coverUrl: String?

    enum CodingKeys: String, CodingKey {
        case series, total, owned
        case coverUrl = "cover_url"
    }

    var id: String { series.lowercased() }
}
