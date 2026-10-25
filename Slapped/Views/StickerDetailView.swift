import SwiftUI
import MapKit
import CoreLocation

struct StickerDetailView: View {
    @Environment(AppState.self) private var app
    @Environment(\.openURL) private var openURL
    @State private var sticker: StickerCard
    @State private var transfers: [Transfer] = []
    @State private var showTrade = false
    @State private var reporting: ReportTarget?
    @State private var confirmBlock = false
    @State private var confirmDelete = false
    @State private var actionError: String?
    @State private var doubleTaps = 0
    @State private var burst = false
    @State private var showZoom = false
    @State private var shareItems: [Any]?
    @State private var showEdit = false
    @Environment(\.dismiss) private var dismiss

    init(sticker: StickerCard) {
        _sticker = State(initialValue: sticker)
    }

    private var isMine: Bool { sticker.ownerId == app.userID }
    private var canDelete: Bool { isMine && sticker.finderId == app.userID && sticker.tradeCount == 0 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                StickerArtwork(url: sticker.imageURL, padding: 32)
                    .frame(height: 340)
                    .overlay {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 110))
                            .foregroundStyle(LinearGradient(colors: [.yellow, .orange, .red], startPoint: .top, endPoint: .bottom))
                            .shadow(color: .orange.opacity(0.6), radius: 16)
                            .scaleEffect(burst ? 1.15 : 0.3)
                            .opacity(burst ? 1 : 0)
                            .allowsHitTesting(false)
                    }
                    .onTapGesture(count: 2) { giveProps() }
                    .onTapGesture { showZoom = true }
                    .accessibilityHint("Double-tap to give props. Tap to view full screen.")

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(sticker.name).font(.largeTitle.weight(.black))
                        Spacer()
                        ValueChip(value: sticker.value, large: true)
                    }
                    if let details = sticker.details {
                        Text(details).foregroundStyle(.secondary)
                    }
                    if let series = sticker.series {
                        NavigationLink(value: Route.series(series)) {
                            Label("Set: \(series)", systemImage: "square.stack.fill")
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(Color.brand.opacity(0.18), in: Capsule())
                        }
                        .buttonStyle(.plain)
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
                    LikeButton(sticker: sticker, doubleTaps: doubleTaps).id(sticker.likedByMe)
                    Spacer()
                }
                .padding(.horizontal, 4)

                CommentsSection(sticker: sticker)
            }
            .padding()
        }
        .background(Color.bg)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Share", systemImage: "square.and.arrow.up") { Task { await prepareShare() } }
                    if sticker.finderId == app.userID {
                        Button("Edit sticker", systemImage: "pencil") { showEdit = true }
                    }
                    if canDelete {
                        Button("Delete sticker", systemImage: "trash", role: .destructive) { confirmDelete = true }
                    }
                    if sticker.finderId != app.userID {
                        Button("Report sticker", systemImage: "flag") { reporting = .sticker(sticker.id) }
                        Button("Block @\(sticker.finderUsername)", systemImage: "hand.raised", role: .destructive) {
                            confirmBlock = true
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .reportDialog(target: $reporting)
        .fullScreenCover(isPresented: $showZoom) { ZoomImageView(url: sticker.imageURL) }
        .sheet(isPresented: $showEdit) {
            EditStickerSheet(sticker: sticker) { await refresh() }
        }
        .sheet(isPresented: Binding(get: { shareItems != nil }, set: { if !$0 { shareItems = nil } })) {
            ActivityShareSheet(items: shareItems ?? []).presentationDetents([.medium, .large])
        }
        .alert("Block @\(sticker.finderUsername)?", isPresented: $confirmBlock) {
            Button("Block", role: .destructive) {
                Task {
                    try? await API.setBlocked(sticker.finderId, blocked: true)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You won't see each other's stickers, comments or activity, and open trades between you are cancelled.")
        }
        .alert("Delete this sticker?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                Task {
                    do {
                        try await API.deleteSticker(sticker)
                        await app.refresh()
                        dismiss()
                    } catch {
                        actionError = error.localizedDescription
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It's removed from the map and your collection. Someone could then log it again.")
        }
        .alert("Something went wrong", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(actionError ?? "") }
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

    private var distanceText: String? {
        guard let here = LocationManager.shared.lastLocation else { return nil }
        let meters = here.distance(from: CLLocation(latitude: sticker.lat, longitude: sticker.lng))
        let measurement = Measurement(value: meters, unit: UnitLength.meters)
        return measurement.formatted(.measurement(width: .abbreviated, usage: .road)) + " away"
    }

    private var locationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader(title: sticker.placeName ?? "Location", systemImage: "mappin.and.ellipse")
                if let distanceText {
                    Text(distanceText).font(.caption.weight(.semibold)).foregroundStyle(.secondary).fixedSize()
                }
            }
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

    private func giveProps() {
        doubleTaps += 1
        withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { burst = true }
        Task {
            try? await Task.sleep(for: .milliseconds(650))
            withAnimation(.easeOut(duration: 0.25)) { burst = false }
        }
    }

    private func prepareShare() async {
        let text = "Check out \"\(sticker.name)\" on Slapped, found by @\(sticker.finderUsername)"
        guard let url = sticker.imageURL,
              let data = try? await URLSession.shared.data(from: url).0,
              let art = UIImage(data: data) else {
            shareItems = [text]
            return
        }
        let renderer = ImageRenderer(content: ShareCardView(sticker: sticker, art: art))
        renderer.scale = 3
        shareItems = renderer.uiImage.map { [$0, text] } ?? [text]
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
