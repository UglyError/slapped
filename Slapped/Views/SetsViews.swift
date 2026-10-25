import SwiftUI

/// Everything tagged with one artist/series, and how much of it you own.
struct SeriesView: View {
    let series: String

    @Environment(AppState.self) private var app
    @State private var stickers: [StickerCard] = []
    @State private var loaded = false

    private var ownedCount: Int { stickers.filter { $0.ownerId == app.userID }.count }
    private var complete: Bool { !stickers.isEmpty && ownedCount == stickers.count }
    private let grid = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(series).font(.largeTitle.weight(.black))
                    if loaded {
                        Text(complete ? "Set complete! You own all \(stickers.count)." : "You own \(ownedCount) of \(stickers.count)")
                            .font(.headline)
                            .foregroundStyle(complete ? Color.brand : .secondary)
                        ProgressView(value: Double(ownedCount), total: Double(max(stickers.count, 1)))
                            .tint(.brand)
                        if !complete && stickers.count >= 3 {
                            Text("Own every sticker in a set of 3+ to earn the Completionist badge. Trade for the ones you're missing.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()

                LazyVGrid(columns: grid, spacing: 16) {
                    ForEach(stickers) { sticker in
                        let mine = sticker.ownerId == app.userID
                        NavigationLink(value: Route.sticker(sticker)) {
                            StickerTile(sticker: sticker)
                                .opacity(mine ? 1 : 0.55)
                                .overlay(alignment: .topLeading) {
                                    Image(systemName: mine ? "checkmark.circle.fill" : "circle.dashed")
                                        .font(.title3)
                                        .foregroundStyle(mine ? Color.brand : .secondary)
                                        .background(Circle().fill(Color.card))
                                        .padding(6)
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding()
        }
        .background(Color.bg)
        .navigationTitle("Set")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            stickers = (try? await API.stickers(inSeries: series)) ?? stickers
            loaded = true
        }
    }
}

/// Card for a set in Explore.
struct SeriesCard: View {
    let summary: SeriesSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                StickerArtwork(url: summary.coverUrl.flatMap(URL.init(string:)), padding: 14)
                Image(systemName: "square.stack.fill")
                    .font(.caption.weight(.bold))
                    .padding(6)
                    .background(.ultraThinMaterial, in: Circle())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(6)
            }
            .aspectRatio(1, contentMode: .fit)
            Text(summary.series).font(.subheadline.weight(.bold)).lineLimit(1)
            HStack(spacing: 6) {
                ProgressView(value: Double(summary.owned), total: Double(max(summary.total, 1))).tint(.brand)
                Text("\(summary.owned)/\(summary.total)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
        .frame(width: 150)
    }
}

/// Lets the finder fix a sticker's name, notes and set after logging it.
struct EditStickerSheet: View {
    let sticker: StickerCard
    let onSaved: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var notes: String
    @State private var series: String
    @State private var saving = false
    @State private var error: String?

    init(sticker: StickerCard, onSaved: @escaping () async -> Void) {
        self.sticker = sticker
        self.onSaved = onSaved
        _name = State(initialValue: sticker.name)
        _notes = State(initialValue: sticker.details ?? "")
        _series = State(initialValue: sticker.series ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") { TextField("What's on it?", text: $name) }
                Section("Notes") { TextField("Optional", text: $notes, axis: .vertical).lineLimit(2...5) }
                Section {
                    TextField("e.g. Obey, Andre the Giant", text: $series)
                } header: {
                    Text("Artist or series")
                } footer: {
                    Text("Stickers with the same artist or series form a set. Collect the whole set to earn badges.")
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Edit sticker")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .bold()
                        .disabled(saving || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() async {
        saving = true
        do {
            try await API.updateSticker(sticker.id, name: String(name.prefix(60)),
                                        details: String(notes.prefix(280)), series: String(series.prefix(40)))
            await onSaved()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
        saving = false
    }
}
