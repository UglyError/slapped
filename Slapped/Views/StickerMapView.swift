import SwiftUI
import MapKit

struct StickerMapView: View {
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var region: MKCoordinateRegion?
    @State private var stickers: [StickerCard] = []
    @State private var selected: StickerCard?

    var body: some View {
        NavigationStack {
            Map(position: $position) {
                UserAnnotation()
                ForEach(stickers) { sticker in
                    Annotation(sticker.name, coordinate: sticker.coordinate, anchor: .bottom) {
                        StickerPin(sticker: sticker, isSelected: selected?.id == sticker.id)
                            .onTapGesture { withAnimation(.snappy) { selected = sticker } }
                    }
                    .annotationTitles(.hidden)
                }
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .mapControls {
                MapUserLocationButton()
                MapCompass()
            }
            .onMapCameraChange(frequency: .onEnd) { context in
                region = context.region
            }
            .task(id: region.map { "\($0.center.latitude),\($0.center.longitude),\($0.span.latitudeDelta)" }) {
                await load()
            }
            .safeAreaInset(edge: .bottom) {
                if let selected {
                    NavigationLink(value: Route.sticker(selected)) {
                        SelectedStickerCard(sticker: selected) { withAnimation { self.selected = nil } }
                    }
                    .buttonStyle(.plain)
                    .padding()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .overlay(alignment: .top) {
                Text("\(stickers.count) stickers in view")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 8)
            }
            .navigationTitle("Map")
            .navigationBarTitleDisplayMode(.inline)
            .withRoutes()
        }
    }

    private func load() async {
        guard let region else { return }
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled, let result = try? await API.inRegion(region) else { return }
        stickers = result
    }
}

private struct StickerPin: View {
    let sticker: StickerCard
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 0) {
            AsyncImage(url: sticker.imageURL) { image in
                image.resizable().scaledToFit().padding(4)
            } placeholder: {
                Image(systemName: "seal.fill").foregroundStyle(Color.brand)
            }
            .frame(width: isSelected ? 56 : 40, height: isSelected ? 56 : 40)
            .background(Color.card, in: Circle())
            .overlay(Circle().stroke(Color.brand, lineWidth: isSelected ? 3 : 2))
            .shadow(radius: 3, y: 2)
            Image(systemName: "triangle.fill")
                .font(.system(size: 9))
                .rotationEffect(.degrees(180))
                .foregroundStyle(Color.brand)
                .offset(y: -2)
        }
        .animation(.snappy, value: isSelected)
    }
}

private struct SelectedStickerCard: View {
    let sticker: StickerCard
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            StickerArtwork(url: sticker.imageURL, padding: 6)
                .frame(width: 72, height: 72)
            VStack(alignment: .leading, spacing: 4) {
                Text(sticker.name).font(.headline).lineLimit(1)
                Text("Found by @\(sticker.finderUsername) · \(sticker.createdAt.timeAgo)")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if let place = sticker.placeName {
                    Label(place, systemImage: "mappin").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing) {
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(.secondary)
                }
                Spacer()
                ValueChip(value: sticker.value)
            }
        }
        .padding(12)
        .card()
    }
}
