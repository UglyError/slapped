import SwiftUI

struct FeedView: View {
    @State private var followingOnly = false
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
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .background(Color.bg)
            .navigationTitle("Feed")
            .refreshable { await load() }
            .task(id: followingOnly) { await load() }
            .withRoutes()
        }
    }

    private func load() async {
        do {
            stickers = try await API.feed(followingOnly: followingOnly)
            error = nil
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
        }
        loaded = true
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
