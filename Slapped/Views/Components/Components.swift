import SwiftUI

struct AvatarView: View {
    let url: String?
    let name: String
    var size: CGFloat = 40

    var body: some View {
        AsyncImage(url: url.flatMap(URL.init(string:))) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                ZStack {
                    Color.brand
                    Text(name.prefix(1).uppercased())
                        .font(.system(size: size * 0.42, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.onBrand)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

/// A cut-out sticker floating on a soft backdrop.
struct StickerArtwork: View {
    let url: URL?
    var padding: CGFloat = 24

    var body: some View {
        ZStack {
            RadialGradient(colors: [Color.brand.opacity(0.18), Color.cardRaised.opacity(0.6)],
                           center: .center, startRadius: 10, endRadius: 260)
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFit()
                        .shadow(color: .black.opacity(0.25), radius: 10, y: 6)
                        .padding(padding)
                case .failure:
                    Image(systemName: "photo").font(.largeTitle).foregroundStyle(.secondary)
                default:
                    ProgressView()
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct ValueChip: View {
    let value: Int
    var large = false

    var body: some View {
        Label("\(value)", systemImage: "sparkles")
            .font(large ? .headline : .caption.weight(.bold))
            .padding(.horizontal, large ? 12 : 8)
            .padding(.vertical, large ? 6 : 4)
            .foregroundStyle(Color.onBrand)
            .background(Color.brand, in: Capsule())
            .accessibilityLabel("\(value) clout")
    }
}

struct LikeButton: View {
    let stickerID: UUID
    /// Bumped by a double-tap elsewhere; gives props if not already given.
    var doubleTaps = 0
    @State private var liked: Bool
    @State private var count: Int

    init(sticker: StickerCard, doubleTaps: Int = 0) {
        stickerID = sticker.id
        self.doubleTaps = doubleTaps
        _liked = State(initialValue: sticker.likedByMe)
        _count = State(initialValue: sticker.likeCount)
    }

    var body: some View {
        Button {
            Task { await toggle() }
        } label: {
            Label("\(count)", systemImage: liked ? "flame.fill" : "flame")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(liked ? Color.orange : Color.secondary)
                .contentTransition(.numericText())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .light), trigger: liked)
        .accessibilityLabel(liked ? "Remove props" : "Give props")
        .onChange(of: doubleTaps) {
            if !liked { Task { await toggle() } }
        }
    }

    private func toggle() async {
        let newValue = !liked
        withAnimation { liked = newValue; count += newValue ? 1 : -1 }
        do {
            try await API.setLike(stickerID, liked: newValue)
        } catch {
            withAnimation { liked = !newValue; count += newValue ? -1 : 1 }
        }
    }
}

/// Square tile used in rails and grids.
struct StickerTile: View {
    let sticker: StickerCard
    var width: CGFloat? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            StickerArtwork(url: sticker.imageURL, padding: 12)
                .aspectRatio(1, contentMode: .fit)
                .rotationEffect(.degrees(sticker.tilt), anchor: .center)
                .overlay(alignment: .topTrailing) { ValueChip(value: sticker.value).padding(6) }
            Text(sticker.name)
                .font(.subheadline.weight(.bold))
                .lineLimit(1)
            Text(sticker.placeName ?? "@\(sticker.finderUsername)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: width)
        .foregroundStyle(.primary)
    }
}

struct SectionHeader: View {
    let title: String
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage { Image(systemName: systemImage).foregroundStyle(Color.brand) }
            Text(title).font(.title3.weight(.heavy))
            Spacer()
        }
    }
}

struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(Color.brand)
            Text(title).font(.headline)
            Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
    }
}

struct StatView: View {
    let value: Int
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value.formatted(.number.notation(.compactName)))
                .font(.title3.weight(.heavy))
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Checkerboard that shows off the transparent background of a cutout.
struct Checkerboard: View {
    var body: some View {
        Canvas { context, size in
            let tile: CGFloat = 12
            for row in 0..<Int(ceil(size.height / tile)) {
                for col in 0..<Int(ceil(size.width / tile)) where (row + col).isMultiple(of: 2) {
                    context.fill(Path(CGRect(x: CGFloat(col) * tile, y: CGFloat(row) * tile, width: tile, height: tile)),
                                 with: .color(.gray.opacity(0.15)))
                }
            }
        }
    }
}

extension StickerCard {
    /// A small, stable tilt (−3°…3°) so grids look slapped-on rather than machine-placed.
    var tilt: Double {
        let seed = id.uuidString.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return Double(seed % 61 - 30) / 10
    }
}

/// Placeholder card shown while the feed loads.
struct SkeletonFeedCard: View {
    @State private var pulse = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Circle().frame(width: 42, height: 42)
                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 4).frame(width: 180, height: 12)
                    RoundedRectangle(cornerRadius: 4).frame(width: 110, height: 10)
                }
            }
            RoundedRectangle(cornerRadius: 16).frame(height: 280)
            RoundedRectangle(cornerRadius: 4).frame(width: 90, height: 12)
        }
        .foregroundStyle(Color.cardRaised)
        .padding(14)
        .card()
        .opacity(pulse ? 0.55 : 1)
        .animation(.easeInOut(duration: 0.9).repeatForever(), value: pulse)
        .onAppear { pulse = true }
        .accessibilityHidden(true)
    }
}
