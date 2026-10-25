import SwiftUI

// MARK: - Comments

struct CommentsSection: View {
    let sticker: StickerCard

    @Environment(AppState.self) private var app
    @State private var comments: [CommentCard] = []
    @State private var draft = ""
    @State private var sending = false
    @State private var error: String?
    @State private var reporting: CommentCard?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Comments", systemImage: "bubble.left.and.bubble.right.fill")

            VStack(alignment: .leading, spacing: 0) {
                if comments.isEmpty {
                    Text("No comments yet. Say something nice.")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .padding(12)
                }
                ForEach(comments) { comment in
                    CommentRow(comment: comment)
                        .contextMenu {
                            if comment.userId == app.userID || sticker.ownerId == app.userID {
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    Task { await delete(comment) }
                                }
                            }
                            if comment.userId != app.userID {
                                Button("Report", systemImage: "flag") { reporting = comment }
                            }
                        }
                    Divider().padding(.leading, 56)
                }

                HStack(spacing: 8) {
                    TextField("Add a comment…", text: $draft, axis: .vertical)
                        .lineLimit(1...4)
                        .textFieldStyle(.plain)
                    Button {
                        Task { await send() }
                    } label: {
                        Image(systemName: "arrow.up.circle.fill").font(.title2)
                    }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending)
                }
                .padding(12)
            }
            .card()

            if let error {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
        }
        .reportDialog(target: Binding(
            get: { reporting.map { ReportTarget.comment($0.id) } },
            set: { if $0 == nil { reporting = nil } }
        ))
        .task { await load() }
    }

    private func load() async {
        comments = (try? await API.comments(on: sticker.id)) ?? comments
    }

    private func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        sending = true
        error = nil
        do {
            try await API.addComment(String(text.prefix(280)), to: sticker.id)
            draft = ""
            await load()
        } catch {
            self.error = error.localizedDescription
        }
        sending = false
    }

    private func delete(_ comment: CommentCard) async {
        try? await API.deleteComment(comment.id)
        await load()
    }
}

private struct CommentRow: View {
    let comment: CommentCard

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            NavigationLink(value: Route.profile(comment.userId)) {
                AvatarView(url: comment.avatarUrl, name: comment.username, size: 34)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("@\(comment.username)").font(.subheadline.weight(.bold))
                    Text(comment.createdAt.timeAgo).font(.caption).foregroundStyle(.secondary)
                }
                Text(comment.body).font(.subheadline)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
    }
}

// MARK: - Reporting

extension View {
    /// Shows a reason picker when `target` is set, files the report, then thanks the user.
    func reportDialog(target: Binding<ReportTarget?>) -> some View {
        modifier(ReportDialog(target: target))
    }
}

private struct ReportDialog: ViewModifier {
    @Binding var target: ReportTarget?
    @State private var thanks = false

    private let reasons = ["Spam", "Offensive or inappropriate", "Harassment or hate", "Not a real sticker", "Something else"]

    func body(content: Content) -> some View {
        content
            .confirmationDialog("Why are you reporting this?",
                                isPresented: Binding(get: { target != nil }, set: { if !$0 { target = nil } }),
                                titleVisibility: .visible) {
                ForEach(reasons, id: \.self) { reason in
                    Button(reason, role: .destructive) {
                        if let current = target {
                            Task {
                                try? await API.report(current, reason: reason)
                                thanks = true
                            }
                        }
                        target = nil
                    }
                }
                Button("Cancel", role: .cancel) { target = nil }
            }
            .alert("Thanks for reporting", isPresented: $thanks) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("We'll review it. Content reported by several people is hidden automatically. You can also block this user from their profile.")
            }
    }
}

// MARK: - Activity

struct ActivityView: View {
    @Environment(AppState.self) private var app
    @State private var items: [ActivityItem] = []
    @State private var loaded = false

    var body: some View {
        List {
            if loaded && items.isEmpty {
                EmptyStateView(systemImage: "bell.slash", title: "Nothing yet",
                               message: "Props, comments, follows and trade offers show up here.")
                    .listRowBackground(Color.clear)
            }
            ForEach(items) { item in
                NavigationLink(value: destination(for: item)) {
                    ActivityRow(item: item, isNew: item.createdAt > app.activitySeenAt)
                }
                .listRowBackground(Color.card)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.bg)
        .navigationTitle("Activity")
        .refreshable { await load() }
        .task { await load() }
        .onDisappear { app.markActivitySeen() }
    }

    private func destination(for item: ActivityItem) -> Route {
        switch item.kind {
        case "trade_offer", "trade_accepted": return .trades
        default:
            if let id = item.stickerId { return .stickerID(id) }
            return .profile(item.actorId)
        }
    }

    private func load() async {
        items = (try? await API.activity()) ?? items
        loaded = true
    }
}

private struct ActivityRow: View {
    let item: ActivityItem
    let isNew: Bool

    private var text: Text {
        let name = Text("@\(item.actorUsername)").bold()
        let sticker = Text(item.stickerName ?? "your sticker").bold()
        switch item.kind {
        case "like": return name + Text(" gave props to ") + sticker
        case "comment": return name + Text(" commented on ") + sticker + Text(": \(item.body ?? "")")
        case "follow": return name + Text(" started following you")
        case "trade_offer": return name + Text(" sent you a trade offer")
        case "trade_accepted": return name + Text(" accepted your trade")
        default: return name
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(url: item.actorAvatarUrl, name: item.actorUsername, size: 40)
                .overlay(alignment: .topLeading) {
                    if isNew { Circle().fill(Color.brand).frame(width: 10, height: 10) }
                }
            VStack(alignment: .leading, spacing: 2) {
                text.font(.subheadline).lineLimit(3)
                Text(item.createdAt.timeAgo).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if let image = item.stickerImageUrl.flatMap(URL.init(string:)) {
                AsyncImage(url: image) { $0.resizable().scaledToFit() } placeholder: { Color.cardRaised }
                    .frame(width: 44, height: 44)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Resolves a sticker id (from activity) into the full detail screen.
struct StickerLoaderView: View {
    let id: UUID
    @State private var sticker: StickerCard?
    @State private var failed = false

    var body: some View {
        Group {
            if let sticker {
                StickerDetailView(sticker: sticker)
            } else if failed {
                EmptyStateView(systemImage: "eye.slash", title: "Sticker unavailable",
                               message: "It may have been removed.")
            } else {
                ProgressView()
            }
        }
        .task {
            do { sticker = try await API.sticker(id) } catch { failed = true }
        }
    }
}

// MARK: - Badges

extension Badge {
    var tierColors: [Color] {
        switch tier {
        case "silver": [Color(white: 0.88), Color(white: 0.62)]
        case "gold": [Color.brand, Color(red: 0.93, green: 0.55, blue: 0.0)]
        case "platinum": [Color(red: 0.80, green: 0.86, blue: 1.0), Color(red: 0.55, green: 0.45, blue: 0.95)]
        default: [Color(red: 0.93, green: 0.66, blue: 0.42), Color(red: 0.70, green: 0.40, blue: 0.20)]  // bronze
        }
    }
}

/// A round medal: tier gradient when earned, grey with a progress ring when locked.
struct BadgeMedal: View {
    let badge: Badge
    var size: CGFloat = 58

    var body: some View {
        ZStack {
            Circle()
                .fill(badge.isEarned
                      ? AnyShapeStyle(LinearGradient(colors: badge.tierColors, startPoint: .topLeading, endPoint: .bottomTrailing))
                      : AnyShapeStyle(Color.cardRaised))
            Circle()
                .strokeBorder(.white.opacity(badge.isEarned ? 0.55 : 0), lineWidth: size * 0.05)
                .padding(size * 0.06)
            Image(systemName: badge.icon)
                .font(.system(size: size * 0.38, weight: .bold))
                .foregroundStyle(badge.isEarned ? Color.onBrand.opacity(0.85) : Color.secondary.opacity(0.6))
            if !badge.isEarned && badge.fraction > 0 {
                Circle()
                    .trim(from: 0, to: badge.fraction)
                    .stroke(Color.brand, style: StrokeStyle(lineWidth: size * 0.06, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
        .frame(width: size, height: size)
        .shadow(color: badge.isEarned ? badge.tierColors[1].opacity(0.35) : .clear, radius: 6, y: 3)
    }
}

struct BadgesRow: View {
    let userID: UUID
    @State private var badges: [Badge] = []
    @State private var loaded = false
    @State private var selected: Badge?

    private var earned: [Badge] { badges.filter(\.isEarned) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeader(title: "Badges", systemImage: "rosette")
                NavigationLink(value: Route.badges(userID)) {
                    Text(badges.count > earned.count ? "\(earned.count)/\(badges.count) · See all" : "See all")
                        .font(.subheadline.weight(.semibold))
                }
                .fixedSize()
            }
            if loaded && earned.isEmpty {
                Text("No badges yet. Log your first sticker to earn one.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(earned) { badge in
                            Button { selected = badge } label: {
                                VStack(spacing: 6) {
                                    BadgeMedal(badge: badge)
                                    Text(badge.title).font(.caption2.weight(.semibold)).lineLimit(1)
                                }
                                .frame(width: 72)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(badge.title): \(badge.detail)")
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .sheet(item: $selected) { BadgeDetailSheet(badge: $0) }
        .task(id: userID) {
            badges = (try? await API.badges(for: userID)) ?? []
            loaded = true
        }
    }
}

struct BadgesView: View {
    let userID: UUID
    @State private var badges: [Badge] = []
    @State private var selected: Badge?

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                let earnedCount = badges.filter(\.isEarned).count
                if !badges.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(earnedCount) of \(badges.count) earned").font(.headline)
                        ProgressView(value: Double(earnedCount), total: Double(max(badges.count, 1)))
                            .tint(.brand)
                    }
                    .padding()
                    .card()
                }
                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(badges.sorted { ($0.isEarned ? 0 : 1, -$0.fraction) < ($1.isEarned ? 0 : 1, -$1.fraction) }) { badge in
                        Button { selected = badge } label: {
                            VStack(spacing: 6) {
                                BadgeMedal(badge: badge, size: 70)
                                Text(badge.title).font(.caption.weight(.bold)).lineLimit(1)
                                if !badge.isEarned, let progress = badge.progress, let target = badge.target {
                                    Text("\(progress)/\(target)").font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding()
        }
        .background(Color.bg)
        .navigationTitle("Badges")
        .sheet(item: $selected) { BadgeDetailSheet(badge: $0) }
        .task { badges = (try? await API.badges(for: userID)) ?? badges }
    }
}

private struct BadgeDetailSheet: View {
    let badge: Badge

    var body: some View {
        VStack(spacing: 14) {
            BadgeMedal(badge: badge, size: 110)
            Text(badge.title).font(.title2.weight(.heavy))
            Text((badge.tier ?? "bronze").capitalized)
                .font(.caption.weight(.bold))
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(LinearGradient(colors: badge.tierColors, startPoint: .leading, endPoint: .trailing), in: Capsule())
                .foregroundStyle(Color.onBrand)
            Text(badge.detail).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if !badge.isEarned, let progress = badge.progress, let target = badge.target {
                ProgressView(value: Double(progress), total: Double(target)).tint(.brand).frame(maxWidth: 220)
                Text("\(progress) of \(target)").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(28)
        .presentationDetents([.height(380)])
    }
}

/// Pops in from the top when a new badge is earned.
struct NewBadgeToast: View {
    let badge: Badge

    var body: some View {
        HStack(spacing: 12) {
            BadgeMedal(badge: badge, size: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text("New badge!").font(.caption.weight(.heavy)).foregroundStyle(.secondary)
                Text(badge.title).font(.headline)
                Text(badge.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.brand, lineWidth: 1.5))
        .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
        .padding(.horizontal)
    }
}

// MARK: - Settings

struct SettingsView: View {
    @Environment(AppState.self) private var app
    @State private var showEdit = false
    @State private var confirmDelete = false
    @State private var deleting = false
    @State private var error: String?

    var body: some View {
        List {
            Section("Account") {
                if app.me != nil {
                    Button("Edit profile", systemImage: "person.crop.circle") { showEdit = true }
                }
                NavigationLink(value: Route.blockedUsers) {
                    Label("Blocked users", systemImage: "hand.raised")
                }
            }
            Section("About") {
                Link(destination: AppConfig.termsURL) { Label("Terms of Use", systemImage: "doc.text") }
                Link(destination: AppConfig.privacyURL) { Label("Privacy Policy", systemImage: "lock.shield") }
                Link(destination: AppConfig.supportURL) { Label("Help & feedback", systemImage: "questionmark.circle") }
                LabeledContent("Version", value: Bundle.main.appVersion)
            }
            Section {
                Button("Sign out", systemImage: "rectangle.portrait.and.arrow.right") {
                    Task { await API.signOut() }
                }
                Button(role: .destructive) { confirmDelete = true } label: {
                    if deleting { ProgressView() } else { Label("Delete account", systemImage: "trash") }
                }
                .disabled(deleting)
            } footer: {
                if let error { Text(error).foregroundStyle(.red) }
            }
        }
        .tint(.primary)
        .navigationTitle("Settings")
        .sheet(isPresented: $showEdit, onDismiss: { Task { await app.refresh() } }) {
            if let me = app.me { EditProfileView(profile: me) }
        }
        .alert("Delete your account?", isPresented: $confirmDelete) {
            Button("Delete forever", role: .destructive) { Task { await deleteAccount() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes your profile, stickers, comments and trades. It can't be undone.")
        }
    }

    private func deleteAccount() async {
        deleting = true
        do {
            try await API.deleteAccount()
        } catch {
            self.error = error.localizedDescription
        }
        deleting = false
    }
}

struct BlockedUsersView: View {
    @State private var users: [BlockedUser] = []
    @State private var loaded = false

    var body: some View {
        List {
            if loaded && users.isEmpty {
                Text("You haven't blocked anyone.").foregroundStyle(.secondary)
            }
            ForEach(users) { entry in
                HStack {
                    AvatarView(url: entry.blocked.avatarUrl, name: entry.blocked.username, size: 32)
                    Text("@\(entry.blocked.username)")
                    Spacer()
                    Button("Unblock") {
                        Task {
                            try? await API.setBlocked(entry.blocked.id, blocked: false)
                            await load()
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .navigationTitle("Blocked users")
        .task { await load() }
    }

    private func load() async {
        users = (try? await API.blockedUsers()) ?? users
        loaded = true
    }
}

extension Bundle {
    var appVersion: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
