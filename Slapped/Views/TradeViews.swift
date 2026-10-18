import SwiftUI

// MARK: - Compose

struct TradeComposerView: View {
    let recipientID: UUID
    var preselected: UUID?

    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var app
    @State private var recipient: ProfileStats?
    @State private var theirs: [StickerCard] = []
    @State private var mine: [StickerCard] = []
    @State private var wanted: Set<UUID> = []
    @State private var giving: Set<UUID> = []
    @State private var message = ""
    @State private var sending = false
    @State private var error: String?
    @State private var loaded = false

    private var getValue: Int { theirs.filter { wanted.contains($0.id) }.reduce(0) { $0 + $1.value } }
    private var giveValue: Int { mine.filter { giving.contains($0.id) }.reduce(0) { $0 + $1.value } }
    private var canSend: Bool { !wanted.isEmpty && !giving.isEmpty && !sending }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    balance

                    section(title: "You get from @\(recipient?.username ?? "…")", stickers: theirs, selection: $wanted,
                            empty: "They have no stickers to trade.")
                    section(title: "You give", stickers: mine, selection: $giving,
                            empty: "You need stickers to trade. Go scan one!")

                    TextField("Add a message (optional)", text: $message, axis: .vertical)
                        .lineLimit(1...3)
                        .padding()
                        .card()

                    if let error {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }
                }
                .padding()
            }
            .background(Color.bg)
            .navigationTitle("Propose trade")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") { Task { await send() } }
                        .bold()
                        .disabled(!canSend)
                }
            }
            .task { await load() }
        }
    }

    private var balance: some View {
        let diff = getValue - giveValue
        return HStack {
            VStack(spacing: 4) {
                Text("YOU GIVE").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                ValueChip(value: giveValue, large: true)
            }
            .frame(maxWidth: .infinity)
            Image(systemName: "arrow.left.arrow.right").font(.title3.weight(.bold)).foregroundStyle(.secondary)
            VStack(spacing: 4) {
                Text("YOU GET").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                ValueChip(value: getValue, large: true)
            }
            .frame(maxWidth: .infinity)
        }
        .padding()
        .card()
        .overlay(alignment: .bottom) {
            if !wanted.isEmpty && !giving.isEmpty {
                Text(diff == 0 ? "Even trade" : diff > 0 ? "You're asking for \(diff) more clout" : "You're offering \(-diff) extra clout")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .offset(y: 22)
            }
        }
        .padding(.bottom, 10)
    }

    private func section(title: String, stickers: [StickerCard], selection: Binding<Set<UUID>>, empty: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: title)
            if stickers.isEmpty && loaded {
                Text(empty).font(.subheadline).foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 12) {
                    ForEach(stickers) { sticker in
                        let selected = selection.wrappedValue.contains(sticker.id)
                        Button {
                            if selected { selection.wrappedValue.remove(sticker.id) } else { selection.wrappedValue.insert(sticker.id) }
                        } label: {
                            StickerTile(sticker: sticker)
                                .overlay(alignment: .topLeading) {
                                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                        .font(.title3)
                                        .foregroundStyle(selected ? Color.brand : Color.secondary)
                                        .background(Circle().fill(Color.card))
                                        .padding(6)
                                }
                                .opacity(selection.wrappedValue.isEmpty || selected ? 1 : 0.6)
                        }
                        .buttonStyle(.plain)
                        .sensoryFeedback(.selection, trigger: selected)
                    }
                }
            }
        }
    }

    private func load() async {
        guard let me = app.userID else { return }
        async let profile = API.profile(recipientID)
        async let theirStickers = API.stickers(ownedBy: recipientID)
        async let myStickers = API.stickers(ownedBy: me)
        recipient = try? await profile
        theirs = (try? await theirStickers) ?? []
        mine = (try? await myStickers) ?? []
        if let preselected, theirs.contains(where: { $0.id == preselected }) { wanted.insert(preselected) }
        loaded = true
    }

    private func send() async {
        sending = true
        error = nil
        do {
            try await API.proposeTrade(to: recipientID, offering: Array(giving), requesting: Array(wanted), message: message)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
        sending = false
    }
}

// MARK: - Inbox

struct TradesView: View {
    @Environment(AppState.self) private var app
    @State private var trades: [Trade] = []
    @State private var tab: Tab = .incoming
    @State private var loaded = false
    @State private var notice: String?

    enum Tab: String, CaseIterable { case incoming = "Incoming", outgoing = "Sent", history = "History" }

    private var visible: [Trade] {
        trades.filter { trade in
            switch tab {
            case .incoming: trade.status == .pending && trade.recipientId == app.userID
            case .outgoing: trade.status == .pending && trade.proposerId == app.userID
            case .history: trade.status != .pending
            }
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                if loaded && visible.isEmpty {
                    EmptyStateView(systemImage: "arrow.left.arrow.right.circle", title: "No trades here",
                                   message: "Find a sticker you like and offer one of yours for it.")
                }
                ForEach(visible) { trade in
                    TradeCard(trade: trade, myID: app.userID) { action in
                        await perform(action, on: trade)
                    }
                }
            }
            .padding()
        }
        .background(Color.bg)
        .navigationTitle("Trades")
        .task { await load() }
        .refreshable { await load() }
        .alert("Trade", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(notice ?? "") }
    }

    private func load() async {
        trades = (try? await API.trades()) ?? trades
        loaded = true
    }

    private func perform(_ action: TradeCard.Action, on trade: Trade) async {
        do {
            switch action {
            case .accept:
                let result = try await API.respondToTrade(trade.id, accept: true)
                notice = result == "accepted"
                    ? "Trade complete! The stickers are in your collection."
                    : "This trade is no longer valid; one of the stickers changed hands."
            case .decline:
                _ = try await API.respondToTrade(trade.id, accept: false)
            case .cancel:
                try await API.cancelTrade(trade.id)
            }
        } catch {
            notice = error.localizedDescription
        }
        await load()
        await app.refresh()
    }
}

struct TradeCard: View {
    enum Action { case accept, decline, cancel }

    let trade: Trade
    let myID: UUID?
    let onAction: (Action) async -> Void
    @State private var working = false

    private var incoming: Bool { trade.recipientId == myID }
    private var other: MiniProfile { incoming ? trade.proposer : trade.recipient }
    /// What I'd receive / give, from my point of view.
    private var iGet: [MiniSticker] { incoming ? trade.offered : trade.requested }
    private var iGive: [MiniSticker] { incoming ? trade.requested : trade.offered }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                NavigationLink(value: Route.profile(other.id)) {
                    AvatarView(url: other.avatarUrl, name: other.username, size: 36)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(incoming ? "@\(other.username) wants to trade" : "Offer to @\(other.username)")
                        .font(.subheadline.weight(.bold))
                    Text(trade.createdAt.timeAgo).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                statusPill
            }

            stickerRow(label: "You get", stickers: iGet)
            stickerRow(label: "You give", stickers: iGive)

            if let message = trade.message {
                Text("“\(message)”").font(.subheadline).italic().foregroundStyle(.secondary)
            }

            if trade.status == .pending {
                HStack(spacing: 10) {
                    if incoming {
                        Button("Decline") { run(.decline) }.buttonStyle(BrandButtonStyle(filled: false))
                        Button("Accept") { run(.accept) }.buttonStyle(BrandButtonStyle())
                    } else {
                        Button("Cancel offer") { run(.cancel) }.buttonStyle(BrandButtonStyle(filled: false))
                    }
                }
                .disabled(working)
            }
        }
        .padding(14)
        .card()
    }

    private var statusPill: some View {
        let (text, color): (String, Color) = switch trade.status {
        case .pending: ("Pending", .brand)
        case .accepted: ("Done", .green)
        case .declined: ("Declined", .red)
        case .cancelled: ("Cancelled", .gray)
        }
        return Text(text)
            .font(.caption.weight(.bold))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(color.opacity(0.2), in: Capsule())
            .foregroundStyle(color == .brand ? Color.primary : color)
    }

    private func stickerRow(label: String, stickers: [MiniSticker]) -> some View {
        HStack(spacing: 8) {
            Text(label.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: 58, alignment: .leading)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(stickers) { sticker in
                        AsyncImage(url: sticker.imageURL) { $0.resizable().scaledToFit() } placeholder: { Color.cardRaised }
                            .frame(width: 48, height: 48)
                            .padding(4)
                            .background(Color.cardRaised, in: RoundedRectangle(cornerRadius: 10))
                            .accessibilityLabel(sticker.name)
                    }
                }
            }
            ValueChip(value: stickers.reduce(0) { $0 + $1.value })
        }
    }

    private func run(_ action: Action) {
        working = true
        Task {
            await onAction(action)
            working = false
        }
    }
}
