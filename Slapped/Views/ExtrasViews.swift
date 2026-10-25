import SwiftUI
import MapKit

// MARK: - First-launch intro

struct OnboardingView: View {
    let onFinish: () -> Void
    @State private var page = 0

    private let pages: [(icon: String, title: String, text: String)] = [
        ("viewfinder", "Spot it. Scan it.",
         "See a sticker out in the wild? Snap it and Slapped peels it right off the wall."),
        ("map.fill", "Claim your spot",
         "Every sticker is pinned where you found it, and only the first hunter can log it."),
        ("arrow.left.arrow.right", "Trade for clout",
         "Offer your stickers for other people's. Popular, well-traded stickers are worth more."),
    ]

    var body: some View {
        VStack(spacing: 24) {
            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { index in
                    VStack(spacing: 22) {
                        ZStack {
                            Circle().fill(Color.brand.opacity(0.18)).frame(width: 210, height: 210)
                            Circle().fill(Color.brand).frame(width: 140, height: 140)
                            Image(systemName: pages[index].icon)
                                .font(.system(size: 58, weight: .bold))
                                .foregroundStyle(Color.onBrand)
                        }
                        Text(pages[index].title).font(.system(size: 30, weight: .black, design: .rounded))
                        Text(pages[index].text)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button(page == pages.count - 1 ? "Start hunting" : "Next") {
                if page < pages.count - 1 { withAnimation { page += 1 } } else { onFinish() }
            }
            .buttonStyle(BrandButtonStyle())
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .background(Color.bg.ignoresSafeArea())
    }
}

// MARK: - Full-screen zoom

struct ZoomImageView: View {
    let url: URL?
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1
    @State private var offset: CGSize = .zero
    @GestureState private var drag: CGSize = .zero

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            AsyncImage(url: url) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                ProgressView().tint(.white)
            }
            .scaleEffect(scale * pinch)
            .offset(x: offset.width + drag.width, y: offset.height + drag.height)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(MagnifyGesture()
                .updating($pinch) { value, state, _ in state = value.magnification }
                .onEnded { value in
                    scale = min(max(scale * value.magnification, 1), 6)
                    if scale == 1 { offset = .zero }
                })
            .simultaneousGesture(DragGesture()
                .updating($drag) { value, state, _ in state = value.translation }
                .onEnded { value in
                    if scale > 1 {
                        offset.width += value.translation.width
                        offset.height += value.translation.height
                    } else if abs(value.translation.height) > 120 {
                        dismiss()   // swipe away when not zoomed
                    }
                })
            .onTapGesture(count: 2) {
                withAnimation(.spring) {
                    scale = scale > 1 ? 1 : 2.5
                    offset = .zero
                }
            }
            .animation(.spring(duration: 0.3), value: drag == .zero)

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(.white.opacity(0.18), in: Circle())
            }
            .padding()
            .accessibilityLabel("Close")
        }
        .statusBarHidden()
    }
}

// MARK: - Share card

/// Branded image used when sharing a sticker.
struct ShareCardView: View {
    let sticker: StickerCard
    let art: UIImage

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text("Slapped").font(.system(size: 22, weight: .black, design: .rounded))
                Spacer()
                Label("\(sticker.value)", systemImage: "sparkles")
                    .font(.system(size: 14, weight: .bold))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color.onBrand.opacity(0.1), in: Capsule())
            }
            Spacer(minLength: 0)
            Image(uiImage: art)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 270, maxHeight: 250)
                .rotationEffect(.degrees(-4))
                .shadow(color: .black.opacity(0.3), radius: 14, y: 10)
            Spacer(minLength: 0)
            VStack(spacing: 4) {
                Text(sticker.name).font(.system(size: 26, weight: .heavy)).lineLimit(2).multilineTextAlignment(.center)
                if let place = sticker.placeName {
                    Label(place, systemImage: "mappin.and.ellipse").font(.system(size: 14, weight: .semibold))
                }
                Text("found by @\(sticker.finderUsername)").font(.system(size: 14))
            }
        }
        .foregroundStyle(Color.onBrand)
        .padding(24)
        .frame(width: 360, height: 450)
        .background(LinearGradient(colors: [Color.brand, Color(red: 1, green: 0.62, blue: 0.05)],
                                   startPoint: .top, endPoint: .bottom))
    }
}

struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Profile finds map

struct FindsMapView: View {
    let stickers: [StickerCard]

    var body: some View {
        if stickers.isEmpty {
            EmptyStateView(systemImage: "map", title: "No finds on the map yet",
                           message: "Stickers this hunter logs will show up here.")
        } else {
            Map(initialPosition: .automatic) {
                ForEach(stickers) { sticker in
                    Annotation(sticker.name, coordinate: sticker.coordinate) {
                        NavigationLink(value: Route.sticker(sticker)) {
                            AsyncImage(url: sticker.imageURL) { $0.resizable().scaledToFit() } placeholder: { Color.brand }
                                .frame(width: 34, height: 34)
                                .padding(3)
                                .background(Color.card, in: Circle())
                                .overlay(Circle().stroke(Color.brand, lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                    }
                    .annotationTitles(.hidden)
                }
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .frame(height: 420)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }
}

// MARK: - Weekly leaderboard

struct LeaderRow: View {
    let rank: Int
    let username: String
    let avatarUrl: String?
    let finds: Int

    var body: some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(rank <= 3 ? Color.brand : .secondary)
                .frame(width: 20)
            AvatarView(url: avatarUrl, name: username, size: 36)
            Text("@\(username)").font(.subheadline.weight(.bold))
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(finds)").font(.subheadline.weight(.heavy))
                Text("this week").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}
