import SwiftUI

struct ExploreView: View {
    @State private var trending: [StickerCard] = []
    @State private var nearby: [StickerCard] = []
    @State private var fresh: [StickerCard] = []
    @State private var hunters: [ProfileStats] = []
    @State private var nearbyUnavailable = false

    @State private var query = ""
    @State private var stickerResults: [StickerCard] = []
    @State private var hunterResults: [ProfileStats] = []

    private let grid = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    discover
                } else {
                    results
                }
            }
            .background(Color.bg)
            .navigationTitle("Explore")
            .searchable(text: $query, prompt: "Stickers, places or hunters")
            .task { await loadAll() }
            .refreshable { await loadAll() }
            .task(id: query) { await search() }
            .withRoutes()
        }
    }

    private var discover: some View {
        VStack(alignment: .leading, spacing: 28) {
            rail("Trending this week", systemImage: "flame.fill", stickers: trending)

            if nearbyUnavailable {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Near you", systemImage: "location.fill").padding(.horizontal)
                    Text("Turn on location to see stickers around you.")
                        .font(.subheadline).foregroundStyle(.secondary).padding(.horizontal)
                }
            } else {
                rail("Near you", systemImage: "location.fill", stickers: nearby,
                     emptyText: "Nothing logged within 5 km yet. Go claim your turf.")
            }

            rail("Fresh finds", systemImage: "sparkles", stickers: fresh)

            if !hunters.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Top hunters", systemImage: "trophy.fill")
                    VStack(spacing: 0) {
                        ForEach(Array(hunters.enumerated()), id: \.element.id) { index, hunter in
                            NavigationLink(value: Route.profile(hunter.id)) {
                                HunterRow(rank: index + 1, hunter: hunter)
                            }
                            .buttonStyle(.plain)
                            if index < hunters.count - 1 { Divider().padding(.leading, 60) }
                        }
                    }
                    .card()
                }
                .padding(.horizontal)
            }
        }
        .padding(.vertical)
    }

    @ViewBuilder
    private func rail(_ title: String, systemImage: String, stickers: [StickerCard], emptyText: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: title, systemImage: systemImage).padding(.horizontal)
            if stickers.isEmpty, let emptyText {
                Text(emptyText).font(.subheadline).foregroundStyle(.secondary).padding(.horizontal)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(stickers) { sticker in
                            NavigationLink(value: Route.sticker(sticker)) {
                                StickerTile(sticker: sticker, width: 150)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }

    private var results: some View {
        VStack(alignment: .leading, spacing: 20) {
            if !hunterResults.isEmpty {
                SectionHeader(title: "Hunters")
                VStack(spacing: 0) {
                    ForEach(hunterResults) { hunter in
                        NavigationLink(value: Route.profile(hunter.id)) {
                            HunterRow(rank: nil, hunter: hunter)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .card()
            }
            if !stickerResults.isEmpty {
                SectionHeader(title: "Stickers")
                LazyVGrid(columns: grid, spacing: 16) {
                    ForEach(stickerResults) { sticker in
                        NavigationLink(value: Route.sticker(sticker)) { StickerTile(sticker: sticker) }
                            .buttonStyle(.plain)
                    }
                }
            }
            if hunterResults.isEmpty && stickerResults.isEmpty {
                EmptyStateView(systemImage: "magnifyingglass", title: "No matches", message: "Try a different name or place.")
            }
        }
        .padding()
    }

    private func loadAll() async {
        async let trendingTask = API.trending()
        async let freshTask = API.feed(followingOnly: false, limit: 20)
        async let huntersTask = API.topHunters()
        trending = (try? await trendingTask) ?? trending
        fresh = (try? await freshTask) ?? fresh
        hunters = (try? await huntersTask) ?? hunters

        do {
            let location = try await LocationManager.shared.currentLocation()
            nearby = try await API.nearby(location.coordinate)
            nearbyUnavailable = false
        } catch is LocationError {
            nearbyUnavailable = true
        } catch {}
    }

    private func search() async {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        try? await Task.sleep(for: .milliseconds(300)) // debounce; cancelled when the query changes
        guard !Task.isCancelled else { return }
        async let stickers = API.searchStickers(text)
        async let people = API.searchHunters(text)
        stickerResults = (try? await stickers) ?? []
        hunterResults = (try? await people) ?? []
    }
}

struct HunterRow: View {
    let rank: Int?
    let hunter: ProfileStats

    var body: some View {
        HStack(spacing: 12) {
            if let rank {
                Text("\(rank)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(rank <= 3 ? Color.brand : .secondary)
                    .frame(width: 20)
            }
            AvatarView(url: hunter.avatarUrl, name: hunter.username, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(hunter.titleName).font(.subheadline.weight(.bold))
                Text("@\(hunter.username)").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(hunter.finds)").font(.subheadline.weight(.heavy))
                Text("finds").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}
