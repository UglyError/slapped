import Foundation
import CoreLocation
import MapKit
import UIKit
import Supabase

enum APIError: LocalizedError {
    case duplicateSticker
    case alreadyLogged(name: String, by: String)
    case imageEncoding
    case server(String)

    var errorDescription: String? {
        switch self {
        case .duplicateSticker: "Someone already logged this sticker here. Find a new one!"
        case .alreadyLogged(let name, let by): "“\(name)” was already logged here by @\(by). Find a new one!"
        case .imageEncoding: "Couldn't process that image."
        case .server(let message): message
        }
    }
}

/// Thin wrapper around the Supabase tables and RPCs in supabase/migrations.
enum API {
    private static let cards = "sticker_cards"

    // MARK: Auth

    static func signUp(email: String, password: String, username: String) async throws -> Bool {
        let response = try await supabase.auth.signUp(
            email: email,
            password: password,
            data: ["username": .string(username.lowercased())],
            redirectTo: AppConfig.authCallbackURL
        )
        // false when the project requires email confirmation
        return response.session != nil
    }

    static func signIn(email: String, password: String) async throws {
        _ = try await supabase.auth.signIn(email: email, password: password)
    }

    static func signOut() async {
        try? await supabase.auth.signOut()
    }

    // MARK: Stickers

    static func feed(followingOnly: Bool, limit: Int = 30, offset: Int = 0) async throws -> [StickerCard] {
        if followingOnly {
            return try await supabase.rpc("following_feed", params: LimitParams(p_limit: 100)).execute().value
        }
        return try await supabase.from(cards).select()
            .order("created_at", ascending: false)
            .range(from: offset, to: offset + limit - 1)
            .execute().value
    }

    static func sticker(_ id: UUID) async throws -> StickerCard {
        try await supabase.from(cards).select()
            .eq("id", value: id.uuidString)
            .single()
            .execute().value
    }

    static func stickers(ownedBy userID: UUID) async throws -> [StickerCard] {
        try await supabase.from(cards).select()
            .eq("owner_id", value: userID.uuidString)
            .order("created_at", ascending: false)
            .execute().value
    }

    static func stickers(foundBy userID: UUID) async throws -> [StickerCard] {
        try await supabase.from(cards).select()
            .eq("finder_id", value: userID.uuidString)
            .order("created_at", ascending: false)
            .execute().value
    }

    static func trending(days: Int = 7, limit: Int = 20) async throws -> [StickerCard] {
        try await supabase.rpc("trending_stickers", params: TrendingParams(p_days: days, p_limit: limit)).execute().value
    }

    static func nearby(_ coordinate: CLLocationCoordinate2D, radius: Double = 5000, limit: Int = 30) async throws -> [StickerCard] {
        try await supabase.rpc("nearby_stickers", params: NearbyParams(
            p_lat: coordinate.latitude, p_lng: coordinate.longitude, p_radius_m: radius, p_limit: limit
        )).execute().value
    }

    static func inRegion(_ region: MKCoordinateRegion) async throws -> [StickerCard] {
        let c = region.center, s = region.span
        return try await supabase.rpc("stickers_in_bounds", params: BoundsParams(
            p_min_lat: c.latitude - s.latitudeDelta / 2, p_min_lng: c.longitude - s.longitudeDelta / 2,
            p_max_lat: c.latitude + s.latitudeDelta / 2, p_max_lng: c.longitude + s.longitudeDelta / 2
        )).execute().value
    }

    static func searchStickers(_ query: String) async throws -> [StickerCard] {
        try await supabase.from(cards).select()
            .or("name.ilike.*\(sanitized(query))*,place_name.ilike.*\(sanitized(query))*")
            .order("value", ascending: false)
            .limit(40)
            .execute().value
    }

    static func setLike(_ stickerID: UUID, liked: Bool) async throws {
        let uid = try await currentUserID()
        if liked {
            try await supabase.from("likes").insert(LikeRow(user_id: uid, sticker_id: stickerID)).execute()
        } else {
            try await supabase.from("likes").delete()
                .eq("user_id", value: uid.uuidString)
                .eq("sticker_id", value: stickerID.uuidString)
                .execute()
        }
    }

    static func transfers(of stickerID: UUID) async throws -> [Transfer] {
        try await supabase.from("sticker_transfers")
            .select("id, created_at, from_user:profiles!sticker_transfers_from_id_fkey(id, username, avatar_url), to_user:profiles!sticker_transfers_to_id_fkey(id, username, avatar_url)")
            .eq("sticker_id", value: stickerID.uuidString)
            .order("created_at", ascending: false)
            .execute().value
    }

    // MARK: Scanning

    static func isDuplicate(hashes: [Int64], at coordinate: CLLocationCoordinate2D) async throws -> Bool {
        try await supabase.rpc("is_duplicate_sticker", params: DuplicateParams(
            p_hashes: hashes, p_lat: coordinate.latitude, p_lng: coordinate.longitude
        )).execute().value
    }

    static func createSticker(image: UIImage, name: String, details: String, hashes: [Int64],
                              coordinate: CLLocationCoordinate2D, placeName: String, series: String = "") async throws -> StickerCard {
        let path = try await uploadPNG(image, name: UUID().uuidString.lowercased())
        do {
            let url = try supabase.storage.from(AppConfig.storageBucket).getPublicURL(path: path)
            let id: UUID = try await supabase.rpc("create_sticker", params: CreateStickerParams(
                p_name: name, p_description: details, p_image_url: url.absoluteString, p_hashes: hashes,
                p_lat: coordinate.latitude, p_lng: coordinate.longitude, p_place_name: placeName,
                p_series: series.isEmpty ? nil : series
            )).execute().value
            return try await sticker(id)
        } catch {
            _ = try? await supabase.storage.from(AppConfig.storageBucket).remove(paths: [path])
            throw mapped(error)
        }
    }

    // MARK: Profiles

    static func profile(_ id: UUID) async throws -> ProfileStats {
        try await supabase.from("profile_stats").select()
            .eq("id", value: id.uuidString)
            .single()
            .execute().value
    }

    static func topHunters(limit: Int = 10) async throws -> [ProfileStats] {
        try await supabase.from("profile_stats").select()
            .gt("finds", value: 0)
            .order("finds", ascending: false)
            .limit(limit)
            .execute().value
    }

    static func searchHunters(_ query: String) async throws -> [ProfileStats] {
        try await supabase.from("profile_stats").select()
            .ilike("username", pattern: "%\(sanitized(query))%")
            .limit(20)
            .execute().value
    }

    static func setFollow(_ userID: UUID, following: Bool) async throws {
        let uid = try await currentUserID()
        if following {
            try await supabase.from("follows").insert(FollowRow(follower_id: uid, following_id: userID)).execute()
        } else {
            try await supabase.from("follows").delete()
                .eq("follower_id", value: uid.uuidString)
                .eq("following_id", value: userID.uuidString)
                .execute()
        }
    }

    static func updateProfile(displayName: String, bio: String, avatar: UIImage?) async throws {
        let uid = try await currentUserID()
        var avatarURL: String?
        if let avatar {
            let path = try await uploadPNG(avatar.resized(maxDimension: 400), name: "avatar-\(UUID().uuidString.lowercased())")
            avatarURL = try supabase.storage.from(AppConfig.storageBucket).getPublicURL(path: path).absoluteString
        }
        try await supabase.from("profiles")
            .update(ProfileUpdate(display_name: displayName, bio: bio, avatar_url: avatarURL))
            .eq("id", value: uid.uuidString)
            .execute()
    }

    // MARK: Trades

    private static let tradeSelect = """
    id, proposer_id, recipient_id, status, message, created_at,
    proposer:profiles!trades_proposer_id_fkey(id, username, avatar_url),
    recipient:profiles!trades_recipient_id_fkey(id, username, avatar_url),
    trade_items(side, sticker:stickers(id, name, image_url, value))
    """

    static func trades() async throws -> [Trade] {
        try await supabase.from("trades").select(tradeSelect)
            .order("created_at", ascending: false)
            .limit(100)
            .execute().value
    }

    static func pendingIncomingCount(for userID: UUID) async throws -> Int {
        try await supabase.from("trades").select("id", head: true, count: .exact)
            .eq("recipient_id", value: userID.uuidString)
            .eq("status", value: "pending")
            .execute().count ?? 0
    }

    static func proposeTrade(to recipient: UUID, offering: [UUID], requesting: [UUID], message: String) async throws {
        do {
            try await supabase.rpc("propose_trade", params: ProposeParams(
                p_recipient: recipient, p_offered: offering, p_requested: requesting, p_message: message
            )).execute()
        } catch { throw mapped(error) }
    }

    /// Returns "accepted", "declined" or "stale".
    static func respondToTrade(_ id: UUID, accept: Bool) async throws -> String {
        do {
            return try await supabase.rpc("respond_trade", params: RespondParams(p_trade: id, p_accept: accept)).execute().value
        } catch { throw mapped(error) }
    }

    static func cancelTrade(_ id: UUID) async throws {
        try await supabase.rpc("cancel_trade", params: TradeIDParams(p_trade: id)).execute()
    }

    // MARK: Helpers

    static func currentUserID() async throws -> UUID {
        try await supabase.auth.session.user.id
    }

    static func uploadPNG(_ image: UIImage, name: String) async throws -> String {
        guard let data = image.pngData() else { throw APIError.imageEncoding }
        let uid = try await currentUserID()
        // storage policy only allows writes under the user's own lowercase uuid folder
        let path = "\(uid.uuidString.lowercased())/\(name).png"
        try await supabase.storage.from(AppConfig.storageBucket)
            .upload(path, data: data, options: FileOptions(contentType: "image/png", upsert: false))
        return path
    }

    private static func sanitized(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: " ")
            .replacingOccurrences(of: "(", with: " ")
            .replacingOccurrences(of: ")", with: " ")
            .replacingOccurrences(of: "%", with: "")
            .replacingOccurrences(of: "*", with: "")
    }

    private static let serverMessages = [
        "duplicate_sticker": "Someone already logged this sticker here. Find a new one!",
        "not_owner_of_offered": "You no longer own one of the stickers you offered.",
        "recipient_not_owner": "They no longer own one of the stickers you asked for.",
        "empty_trade": "Pick at least one sticker on each side.",
        "cannot_trade_with_self": "You can't trade with yourself.",
        "trade_not_pending": "This trade has already been settled.",
        "trade_not_found": "Trade not found.",
        "comments_body_check": "Comments must be 1 to 280 characters.",
    ]

    static func mapped(_ error: Error) -> Error {
        guard let pg = error as? PostgrestError else { return error }
        if pg.message.contains("duplicate_sticker") { return APIError.duplicateSticker }
        if let friendly = serverMessages.first(where: { pg.message.contains($0.key) })?.value {
            return APIError.server(friendly)
        }
        return error
    }
}

// MARK: - Request bodies (keys match the SQL parameter / column names)

private struct LimitParams: Encodable { let p_limit: Int }
private struct TrendingParams: Encodable { let p_days: Int; let p_limit: Int }
private struct NearbyParams: Encodable { let p_lat: Double; let p_lng: Double; let p_radius_m: Double; let p_limit: Int }
private struct BoundsParams: Encodable { let p_min_lat: Double; let p_min_lng: Double; let p_max_lat: Double; let p_max_lng: Double }
private struct DuplicateParams: Encodable { let p_hashes: [Int64]; let p_lat: Double; let p_lng: Double }
private struct CreateStickerParams: Encodable {
    let p_name: String; let p_description: String; let p_image_url: String; let p_hashes: [Int64]
    let p_lat: Double; let p_lng: Double; let p_place_name: String
    let p_series: String?
}
private struct ProposeParams: Encodable { let p_recipient: UUID; let p_offered: [UUID]; let p_requested: [UUID]; let p_message: String }
private struct RespondParams: Encodable { let p_trade: UUID; let p_accept: Bool }
private struct TradeIDParams: Encodable { let p_trade: UUID }
private struct LikeRow: Encodable { let user_id: UUID; let sticker_id: UUID }
private struct FollowRow: Encodable { let follower_id: UUID; let following_id: UUID }
private struct ProfileUpdate: Encodable {
    let display_name: String
    let bio: String
    let avatar_url: String?

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(display_name, forKey: .display_name)
        try c.encode(bio, forKey: .bio)
        // leave the existing avatar alone unless a new one was uploaded
        try c.encodeIfPresent(avatar_url, forKey: .avatar_url)
    }

    enum CodingKeys: String, CodingKey { case display_name, bio, avatar_url }
}
