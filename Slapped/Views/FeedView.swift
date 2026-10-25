import SwiftUI

struct FeedView: View {
    @Environment(AppState.self) private var app
    @State private var followingOnly = false
    @State private var canLoadMore = true
    @State private var stickers: [StickerCard] = []
    @State private var loaded = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    Picker("Feed", selection: $followingOnly) {
                        Text("Everyone").tag(false)
                        Text("Friends").tag(true)
                    }
                    .pickerStyle(.segmented)

                    if let error {
                        EmptyStateView(systemImage: "wifi.exclamationmark", title: "Couldn't load the feed", message: error)
                    } else if loaded && stickers.isEmpty {
                        EmptyStateView(
                            systemImage: "binoculars.fill",
                            title: followingOnly ? "Quiet out here" : "No finds yet",
                            message: followingOnly ? "Follow other hunters to see their finds." : "Be the first: tap Scan and log a sticker."
                        )
                    }

                    ForEach(stickers) { sticker in
                        StickerFeedCard(sticker: sticker)
                            .onAppear {
                                if sticker.id == stickers.last?.id { Task { await loadMore() } }
                            }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .background(Color.bg)
            .navigationTitle("Feed")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(value: Route.activity) {
                        Image(systemName: app.unseenActivity > 0 ? "bell.badge.fill" : "bell")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(Color.brand, Color.primary)
                    }
                    .accessibilityLabel("Activity")
                }
            }
            .refreshable {
                await load()
                await app.refresh()
            }
            .task(id: followingOnly) { await load() }
            .withRoutes()
        }
    }

    private func load() async {
        do {
            stickers = try await API.feed(followingOnly: followingOnly)
            canLoadMore = !followingOnly && stickers.count >= 30
            error = nil
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
        }
        loaded = true
    }

    private func loadMore() async {
        guard canLoadMore else { return }
        canLoadMore = false
        guard let more = try? await API.feed(followingOnly: false, offset: stickers.count) else { return }
        let known = Set(stickers.map(\.id))
        stickers += more.filter { !known.contains($0.id) }
        canLoadMore = more.count >= 30
    }
}

/// The "check-in" card: who found what, where, and when.
struct StickerFeedCard: View {
    let sticker: StickerCard

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                NavigationLink(value: Route.profile(sticker.finderId)) {
                    AvatarView(url: sticker.finderAvatarUrl, name: sticker.finderUsername, size: 42)
                }
                VStack(alignment: .leading, spacing: 3) {
                    (Text(sticker.finderUsername).bold()
                        + Text(" found ").foregroundColor(.secondary)
                        + Text(sticker.name).bold())
                        .font(.subheadline)
                        .lineLimit(2)
                    Label(sticker.placeName ?? "Somewhere out there", systemImage: "mappin.and.ellipse")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Text(sticker.createdAt.timeAgo)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            NavigationLink(value: Route.sticker(sticker)) {
                StickerArtwork(url: sticker.imageURL)
                    .frame(height: 280)
            }

            if let details = sticker.details {
                Text(details).font(.subheadline)
            }

            HStack(spacing: 16) {
                LikeButton(sticker: sticker)
                NavigationLink(value: Route.sticker(sticker)) {
                    Label("\(sticker.commentCount ?? 0)", systemImage: "bubble.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                if sticker.wasTraded {
                    Label("with @\(sticker.ownerUsername)", systemImage: "arrow.left.arrow.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                ValueChip(value: sticker.value)
            }
        }
        .padding(14)
        .card()
    }
}
