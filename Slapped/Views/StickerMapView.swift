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
                ForEach(clusters.filter { $0.stickers.count == 1 }) { cluster in
                    Annotation(cluster.stickers[0].name, coordinate: cluster.center, anchor: .bottom) {
                        StickerPin(sticker: cluster.stickers[0], isSelected: selected?.id == cluster.stickers[0].id)
                            .onTapGesture { withAnimation(.snappy) { selected = cluster.stickers[0] } }
                    }
                    .annotationTitles(.hidden)
                }
                ForEach(clusters.filter { $0.stickers.count > 1 }) { cluster in
                    Annotation("\(cluster.stickers.count) stickers", coordinate: cluster.center) {
                        ClusterBubble(count: cluster.stickers.count)
                            .onTapGesture { zoom(into: cluster) }
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

    /// Groups pins that would overlap at the current zoom into one bubble.
    private var clusters: [PinCluster] {
        guard let region else {
            return stickers.map { PinCluster(id: $0.id.uuidString, stickers: [$0], center: $0.coordinate) }
        }
        let cellLat = max(region.span.latitudeDelta / 9, 0.000_05)
        let cellLng = max(region.span.longitudeDelta / 6, 0.000_05)
        let groups = Dictionary(grouping: stickers) { sticker in
            "\(Int(floor(sticker.lat / cellLat))):\(Int(floor(sticker.lng / cellLng)))"
        }
        return groups.map { key, items in
            let lat = items.map(\.lat).reduce(0, +) / Double(items.count)
            let lng = items.map(\.lng).reduce(0, +) / Double(items.count)
            return PinCluster(id: items.count == 1 ? items[0].id.uuidString : key, stickers: items,
                              center: CLLocationCoordinate2D(latitude: lat, longitude: lng))
        }
    }

    private func zoom(into cluster: PinCluster) {
        let lats = cluster.stickers.map(\.lat), lngs = cluster.stickers.map(\.lng)
        guard let minLat = lats.min(), let maxLat = lats.max(), let minLng = lngs.min(), let maxLng = lngs.max() else { return }
        let span = MKCoordinateSpan(latitudeDelta: max((maxLat - minLat) * 1.8, 0.002),
                                    longitudeDelta: max((maxLng - minLng) * 1.8, 0.002))
        withAnimation(.easeInOut) {
            position = .region(MKCoordinateRegion(center: cluster.center, span: span))
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

private struct PinCluster: Identifiable {
    let id: String
    let stickers: [StickerCard]
    let center: CLLocationCoordinate2D
}

private struct ClusterBubble: View {
    let count: Int

    var body: some View {
        let size = min(64, 34 + CGFloat(count).squareRoot() * 4)
        Text("\(count)")
            .font(.system(size: size * 0.38, weight: .heavy, design: .rounded))
            .foregroundStyle(Color.onBrand)
            .frame(width: size, height: size)
            .background(Color.brand, in: Circle())
            .overlay(Circle().stroke(.white, lineWidth: 3))
            .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
    }
}
