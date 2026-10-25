import Foundation
import Supabase

enum ReportTarget: Hashable {
    case sticker(UUID)
    case comment(UUID)
    case user(UUID)
}

extension API {
    // MARK: Comments

    static func comments(on stickerID: UUID) async throws -> [CommentCard] {
        try await supabase.from("comment_cards").select()
            .eq("sticker_id", value: stickerID.uuidString)
            .order("created_at", ascending: true)
            .limit(200)
            .execute().value
    }

    static func addComment(_ body: String, to stickerID: UUID) async throws {
        let uid = try await currentUserID()
        do {
            try await supabase.from("comments")
                .insert(CommentRow(sticker_id: stickerID, user_id: uid, body: body))
                .execute()
        } catch { throw mapped(error) }
    }

    static func deleteComment(_ id: UUID) async throws {
        try await supabase.from("comments").delete().eq("id", value: id.uuidString).execute()
    }

    // MARK: Activity & badges

    static func activity(limit: Int = 60) async throws -> [ActivityItem] {
        try await supabase.rpc("my_activity", params: ActivityParams(p_limit: limit)).execute().value
    }

    /// Every badge with progress. Falls back to earned-only if migration 0003 isn't applied yet.
    static func badges(for userID: UUID) async throws -> [Badge] {
        do {
            return try await supabase.rpc("badge_progress", params: UserParams(p_user: userID)).execute().value
        } catch {
            return try await supabase.rpc("user_badges", params: UserParams(p_user: userID)).execute().value
        }
    }

    // MARK: Sets & editing

    static func updateSticker(_ id: UUID, name: String, details: String, series: String) async throws {
        do {
            try await supabase.rpc("update_sticker", params: UpdateStickerParams(
                p_sticker: id, p_name: name, p_description: details, p_series: series
            )).execute()
        } catch { throw mapped(error) }
    }

    static func seriesOverview() async throws -> [SeriesSummary] {
        try await supabase.rpc("series_overview").execute().value
    }

    static func stickers(inSeries series: String) async throws -> [StickerCard] {
        // exact, case-insensitive match (escape LIKE wildcards)
        let pattern = series.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
        return try await supabase.from("sticker_cards").select()
            .ilike("series", pattern: pattern)
            .order("value", ascending: false)
            .execute().value
    }

    // MARK: Leaderboard

    struct WeeklyHunter: Identifiable {
        let id: UUID
        let username: String
        let avatarUrl: String?
        let finds: Int
    }

    static func weeklyHunters(limit: Int = 10) async throws -> [WeeklyHunter] {
        let since = ISO8601DateFormatter().string(from: Date.now.addingTimeInterval(-7 * 86_400))
        let rows: [FinderRow] = try await supabase.from("sticker_cards")
            .select("finder_id, finder_username, finder_avatar_url")
            .gte("created_at", value: since)
            .limit(2000)
            .execute().value
        let grouped = Dictionary(grouping: rows, by: \.finder_id)
        return grouped.values
            .compactMap { group in
                group.first.map { WeeklyHunter(id: $0.finder_id, username: $0.finder_username,
                                               avatarUrl: $0.finder_avatar_url, finds: group.count) }
            }
            .sorted { $0.finds > $1.finds }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: Moderation

    static func report(_ target: ReportTarget, reason: String) async throws {
        var params = ReportParams(p_reason: reason)
        switch target {
        case .sticker(let id): params.p_sticker = id
        case .comment(let id): params.p_comment = id
        case .user(let id): params.p_user = id
        }
        try await supabase.rpc("report_content", params: params).execute()
    }

    static func setBlocked(_ userID: UUID, blocked: Bool) async throws {
        let uid = try await currentUserID()
        if blocked {
            try await supabase.from("blocks").insert(BlockRow(blocker_id: uid, blocked_id: userID)).execute()
        } else {
            try await supabase.from("blocks").delete()
                .eq("blocker_id", value: uid.uuidString)
                .eq("blocked_id", value: userID.uuidString)
                .execute()
        }
    }

    static func blockedUsers() async throws -> [BlockedUser] {
        try await supabase.from("blocks")
            .select("blocked:profiles!blocks_blocked_id_fkey(id, username, avatar_url)")
            .order("created_at", ascending: false)
            .execute().value
    }

    /// Only works for your own untraded finds (enforced by row level security).
    static func deleteSticker(_ sticker: StickerCard) async throws {
        try await supabase.from("stickers").delete().eq("id", value: sticker.id.uuidString).execute()
        if let range = sticker.imageUrl.range(of: "/\(AppConfig.storageBucket)/") {
            let path = String(sticker.imageUrl[range.upperBound...])
            _ = try? await supabase.storage.from(AppConfig.storageBucket).remove(paths: [path])
        }
    }

    // MARK: Account

    static func verifySignUp(email: String, code: String) async throws {
        _ = try await supabase.auth.verifyOTP(email: email, token: code, type: .signup)
    }

    static func resendSignUpCode(email: String) async throws {
        try await supabase.auth.resend(email: email, type: .signup, emailRedirectTo: AppConfig.authCallbackURL)
    }

    static func sendPasswordReset(email: String) async throws {
        try await supabase.auth.resetPasswordForEmail(email, redirectTo: AppConfig.authCallbackURL)
        UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: "recoveryRequestedAt")
    }

    /// True (once) if a password reset was requested in the last hour.
    static func consumeRecoveryRequest() -> Bool {
        let requested = UserDefaults.standard.double(forKey: "recoveryRequestedAt")
        UserDefaults.standard.removeObject(forKey: "recoveryRequestedAt")
        return requested > 0 && Date.now.timeIntervalSince1970 - requested < 3600
    }

    static func resetPassword(email: String, code: String, newPassword: String) async throws {
        _ = try await supabase.auth.verifyOTP(email: email, token: code, type: .recovery)
        _ = try await supabase.auth.update(user: UserAttributes(password: newPassword))
    }

    static func setNewPassword(_ password: String) async throws {
        _ = try await supabase.auth.update(user: UserAttributes(password: password))
    }

    static func deleteAccount() async throws {
        let uid = try await currentUserID()
        let folder = uid.uuidString.lowercased()
        if let files = try? await supabase.storage.from(AppConfig.storageBucket).list(path: folder), !files.isEmpty {
            _ = try? await supabase.storage.from(AppConfig.storageBucket)
                .remove(paths: files.map { "\(folder)/\($0.name)" })
        }
        try await supabase.rpc("delete_account").execute()
        try? await supabase.auth.signOut()
    }
}

private struct UpdateStickerParams: Encodable { let p_sticker: UUID; let p_name: String; let p_description: String; let p_series: String }
private struct FinderRow: Decodable { let finder_id: UUID; let finder_username: String; let finder_avatar_url: String? }
private struct CommentRow: Encodable { let sticker_id: UUID; let user_id: UUID; let body: String }
private struct BlockRow: Encodable { let blocker_id: UUID; let blocked_id: UUID }
private struct ActivityParams: Encodable { let p_limit: Int }
private struct UserParams: Encodable { let p_user: UUID }
private struct ReportParams: Encodable {
    let p_reason: String
    var p_sticker: UUID?
    var p_comment: UUID?
    var p_user: UUID?
}
