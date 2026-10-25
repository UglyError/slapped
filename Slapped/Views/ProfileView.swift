import SwiftUI
import PhotosUI

struct ProfileView: View {
    let userID: UUID

    @Environment(AppState.self) private var app
    @State private var profile: ProfileStats?
    @State private var collection: [StickerCard] = []
    @State private var finds: [StickerCard] = []
    @State private var showingFinds = false
    @State private var showEdit = false
    @State private var showTrade = false
    @State private var reporting: ReportTarget?
    @State private var confirmBlock = false

    private var isMe: Bool { userID == app.userID }
    private var shown: [StickerCard] { showingFinds ? finds : collection }
    private let grid = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if let profile { header(profile) }

                Picker("", selection: $showingFinds) {
                    Text("Collection (\(collection.count))").tag(false)
                    Text("Finds (\(finds.count))").tag(true)
                }
                .pickerStyle(.segmented)

                if shown.isEmpty {
                    EmptyStateView(
                        systemImage: "seal",
                        title: showingFinds ? "No finds yet" : "Empty collection",
                        message: isMe ? "Head out and scan your first sticker." : "Nothing here yet."
                    )
                } else {
                    LazyVGrid(columns: grid, spacing: 16) {
                        ForEach(shown) { sticker in
                            NavigationLink(value: Route.sticker(sticker)) { StickerTile(sticker: sticker) }
                                .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding()
        }
        .background(Color.bg)
        .navigationTitle(profile.map { "@\($0.username)" } ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if isMe {
                    NavigationLink(value: Route.settings) { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                } else if let profile {
                    Menu {
                        Button("Report @\(profile.username)", systemImage: "flag") { reporting = .user(userID) }
                        if profile.blockedByMe == true {
                            Button("Unblock", systemImage: "hand.raised.slash") {
                                Task {
                                    try? await API.setBlocked(userID, blocked: false)
                                    await load()
                                }
                            }
                        } else {
                            Button("Block", systemImage: "hand.raised", role: .destructive) { confirmBlock = true }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .reportDialog(target: $reporting)
        .alert("Block @\(profile?.username ?? "")?", isPresented: $confirmBlock) {
            Button("Block", role: .destructive) {
                Task {
                    try? await API.setBlocked(userID, blocked: true)
                    await load()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You won't see each other's stickers, comments or activity, and open trades between you are cancelled.")
        }
        .sheet(isPresented: $showEdit, onDismiss: { Task { await load() } }) {
            if let profile { EditProfileView(profile: profile) }
        }
        .sheet(isPresented: $showTrade) {
            TradeComposerView(recipientID: userID)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func header(_ profile: ProfileStats) -> some View {
        VStack(spacing: 14) {
            AvatarView(url: profile.avatarUrl, name: profile.username, size: 88)
                .overlay(Circle().stroke(Color.brand, lineWidth: 3))
            VStack(spacing: 4) {
                Text(profile.titleName).font(.title2.weight(.heavy))
                Text("@\(profile.username)").font(.subheadline).foregroundStyle(.secondary)
                if let bio = profile.bio, !bio.isEmpty {
                    Text(bio).font(.subheadline).multilineTextAlignment(.center).padding(.top, 4)
                }
            }

            HStack {
                StatView(value: profile.finds, label: "Finds")
                StatView(value: profile.owned, label: "Owned")
                StatView(value: profile.collectionValue, label: "Clout")
                StatView(value: profile.followers, label: "Followers")
            }
            .padding(.vertical, 12)
            .card()

            BadgesRow(userID: userID)

            if isMe {
                NavigationLink(value: Route.trades) {
                    HStack {
                        Label("Trades", systemImage: "arrow.left.arrow.right")
                            .font(.headline)
                        Spacer()
                        if app.pendingIncoming > 0 {
                            Text("\(app.pendingIncoming) new")
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Color.brand, in: Capsule())
                                .foregroundStyle(Color.onBrand)
                        }
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                    .padding()
                    .card()
                }
                .buttonStyle(.plain)
            } else if profile.blockedByMe == true {
                Label("You blocked this user", systemImage: "hand.raised.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 10) {
                    Button(profile.followedByMe ? "Following" : "Follow") {
                        Task {
                            try? await API.setFollow(userID, following: !profile.followedByMe)
                            await load()
                        }
                    }
                    .buttonStyle(BrandButtonStyle(filled: !profile.followedByMe))

                    Button { showTrade = true } label: { Label("Trade", systemImage: "arrow.left.arrow.right") }
                        .buttonStyle(BrandButtonStyle(filled: false))
                        .disabled(collection.isEmpty)
                }
            }
        }
    }

    private func load() async {
        async let p = API.profile(userID)
        async let c = API.stickers(ownedBy: userID)
        async let f = API.stickers(foundBy: userID)
        profile = (try? await p) ?? profile
        collection = (try? await c) ?? collection
        finds = (try? await f) ?? finds
        if isMe { await app.refresh() }
    }
}

struct EditProfileView: View {
    let profile: ProfileStats

    @Environment(\.dismiss) private var dismiss
    @State private var displayName: String
    @State private var bio: String
    @State private var photoItem: PhotosPickerItem?
    @State private var avatar: UIImage?
    @State private var saving = false
    @State private var error: String?

    init(profile: ProfileStats) {
        self.profile = profile
        _displayName = State(initialValue: profile.displayName ?? "")
        _bio = State(initialValue: profile.bio ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            Group {
                                if let avatar {
                                    Image(uiImage: avatar).resizable().scaledToFill()
                                        .frame(width: 96, height: 96).clipShape(Circle())
                                } else {
                                    AvatarView(url: profile.avatarUrl, name: profile.username, size: 96)
                                }
                            }
                            .overlay(alignment: .bottomTrailing) {
                                Image(systemName: "camera.circle.fill")
                                    .font(.title)
                                    .foregroundStyle(Color.onBrand, Color.brand)
                            }
                        }
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }
                Section("Display name") {
                    TextField("Your name", text: $displayName)
                }
                Section("Bio") {
                    TextField("What do you hunt?", text: $bio, axis: .vertical).lineLimit(2...4)
                }
                if let error {
                    Text(error).foregroundStyle(.red)
                }
            }
            .navigationTitle("Edit profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }.bold().disabled(saving)
                }
            }
            .onChange(of: photoItem) { _, item in
                Task {
                    if let data = try? await item?.loadTransferable(type: Data.self) {
                        avatar = UIImage(data: data)
                    }
                }
            }
        }
    }

    private func save() async {
        saving = true
        do {
            try await API.updateProfile(
                displayName: String(displayName.prefix(40)),
                bio: String(bio.prefix(160)),
                avatar: avatar
            )
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
        saving = false
    }
}
