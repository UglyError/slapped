import SwiftUI
import MapKit

struct StickerDetailView: View {
    @Environment(AppState.self) private var app
    @Environment(\.openURL) private var openURL
    @State private var sticker: StickerCard
    @State private var transfers: [Transfer] = []
    @State private var showTrade = false

    init(sticker: StickerCard) {
        _sticker = State(initialValue: sticker)
    }

    private var isMine: Bool { sticker.ownerId == app.userID }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                StickerArtwork(url: sticker.imageURL, padding: 32)
                    .frame(height: 340)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(sticker.name).font(.largeTitle.weight(.black))
                        Spacer()
                        ValueChip(value: sticker.value, large: true)
                    }
                    if let details = sticker.details {
                        Text(details).foregroundStyle(.secondary)
                    }
                }

                HStack {
                    StatView(value: sticker.likeCount, label: "Props")
                    Divider().frame(height: 32)
                    StatView(value: sticker.tradeCount, label: "Trades")
                    Divider().frame(height: 32)
                    StatView(value: sticker.value, label: "Clout")
                }
                .padding(.vertical, 12)
                .card()

                VStack(spacing: 0) {
                    personRow(title: "Found by", id: sticker.finderId, username: sticker.finderUsername,
                              avatar: sticker.finderAvatarUrl, trailing: sticker.createdAt.formatted(date: .abbreviated, time: .omitted))
                    Divider().padding(.leading, 60)
                    personRow(title: "Owned by", id: sticker.ownerId, username: sticker.ownerUsername,
                              avatar: sticker.ownerAvatarUrl, trailing: nil)
                }
                .card()

                locationSection

                if !transfers.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "Trade history", systemImage: "arrow.left.arrow.right")
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(transfers) { transfer in
                                HStack {
                                    Text("@\(transfer.fromUser.username)").bold()
                                    Image(systemName: "arrow.right").foregroundStyle(.secondary)
                                    Text("@\(transfer.toUser.username)").bold()
                                    Spacer()
                                    Text(transfer.createdAt.timeAgo).foregroundStyle(.secondary)
                                }
                                .font(.subheadline)
                                .padding(12)
                                if transfer.id != transfers.last?.id { Divider() }
                            }
                        }
                        .card()
                    }
                }

                HStack {
                    LikeButton(sticker: sticker).id(sticker.likedByMe)
                    Spacer()
                }
                .padding(.horizontal, 4)
            }
            .padding()
        }
        .background(Color.bg)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if !isMine {
                Button { showTrade = true } label: {
                    Label("Offer a trade for this", systemImage: "arrow.left.arrow.right")
                }
                .buttonStyle(BrandButtonStyle())
                .padding()
                .background(.bar)
            }
        }
        .sheet(isPresented: $showTrade) {
            TradeComposerView(recipientID: sticker.ownerId, preselected: sticker.id)
        }
        .task { await refresh() }
        .refreshable { await refresh() }
    }

    private func personRow(title: String, id: UUID, username: String, avatar: String?, trailing: String?) -> some View {
        NavigationLink(value: Route.profile(id)) {
            HStack(spacing: 12) {
                AvatarView(url: avatar, name: username, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title.uppercased()).font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                    Text("@\(username)").font(.subheadline.weight(.bold))
                }
                Spacer()
                if let trailing { Text(trailing).font(.caption).foregroundStyle(.secondary) }
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
            }
            .padding(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var locationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: sticker.placeName ?? "Location", systemImage: "mappin.and.ellipse")
            Map(initialPosition: .camera(MapCamera(centerCoordinate: sticker.coordinate, distance: 900)),
                interactionModes: []) {
                Annotation(sticker.name, coordinate: sticker.coordinate) {
                    AsyncImage(url: sticker.imageURL) { $0.resizable().scaledToFit() } placeholder: { Color.brand }
                        .frame(width: 44, height: 44)
                        .padding(4)
                        .background(Color.card, in: Circle())
                        .overlay(Circle().stroke(Color.brand, lineWidth: 2))
                }
            }
            .frame(height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .onTapGesture { openInMaps() }
            Button("Open in Maps", systemImage: "arrow.up.right.square", action: openInMaps)
                .font(.subheadline.weight(.semibold))
        }
    }

    private func openInMaps() {
        let q = sticker.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "https://maps.apple.com/?ll=\(sticker.lat),\(sticker.lng)&q=\(q)") {
            openURL(url)
        }
    }

    private func refresh() async {
        if let latest = try? await API.sticker(sticker.id) { sticker = latest }
        transfers = (try? await API.transfers(of: sticker.id)) ?? []
    }
}
