import SwiftUI

/// Shows the cut-out lying flat on the photo, curls a corner back to reveal the paper
/// backing, then lifts the whole sticker off the wall.
struct PeelRevealView: View {
    let sticker: UIImage
    let photo: UIImage?

    /// 1 = flat; smaller values fold the bottom-right corner further back.
    @State private var fold: CGFloat = 1
    @State private var lifted = false

    var body: some View {
        GeometryReader { geo in
            let size = fitted(sticker.size, in: CGSize(width: geo.size.width - 56, height: geo.size.height - 56))
            let crease = (size.width + size.height) * fold
            ZStack {
                background(in: geo.size)

                ZStack(alignment: .topLeading) {
                    // still stuck to the wall
                    Image(uiImage: sticker)
                        .resizable()
                        .frame(width: size.width, height: size.height)
                        .mask(FoldMask(crease: crease, peeled: false))
                    // the peeled-back flap: the sticker's paper backing, mirrored across the crease
                    Image(uiImage: sticker)
                        .resizable()
                        .renderingMode(.template)
                        .foregroundStyle(LinearGradient(colors: [Color(white: 0.99), Color(white: 0.80)],
                                                        startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: size.width, height: size.height)
                        .mask(FoldMask(crease: crease, peeled: true))
                        .modifier(MirrorAcrossCrease(crease: crease))
                        .shadow(color: .black.opacity(0.35), radius: 5, x: -2, y: -2)
                }
                .frame(width: size.width, height: size.height)
                .scaleEffect(lifted ? 1.07 : 1)
                .rotation3DEffect(.degrees(lifted ? 9 : 0), axis: (x: 1, y: -1, z: 0), perspective: 0.6)
                .shadow(color: .black.opacity(lifted ? 0.45 : 0.12), radius: lifted ? 22 : 2, y: lifted ? 16 : 1)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .onAppear(perform: peel)
        .sensoryFeedback(.impact(weight: .light), trigger: fold < 1)
        .sensoryFeedback(.impact(weight: .heavy), trigger: lifted)
    }

    @ViewBuilder
    private func background(in size: CGSize) -> some View {
        if let photo {
            Image(uiImage: photo)
                .resizable()
                .scaledToFill()
                .frame(width: size.width, height: size.height)
                .clipped()
                .blur(radius: lifted ? 16 : 3)
                .overlay(Color.black.opacity(lifted ? 0.5 : 0.15))
        } else {
            Checkerboard()
        }
    }

    private func peel() {
        fold = 1
        lifted = false
        withAnimation(.easeInOut(duration: 0.75).delay(0.3)) { fold = 0.6 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.15) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.62)) {
                fold = 1
                lifted = true
            }
        }
    }

    private func fitted(_ image: CGSize, in box: CGSize) -> CGSize {
        guard image.width > 0, image.height > 0, box.width > 0, box.height > 0 else { return .zero }
        let ratio = min(box.width / image.width, box.height / image.height)
        return CGSize(width: image.width * ratio, height: image.height * ratio)
    }
}

/// The part of the rect on one side of the crease line x + y = crease.
private struct FoldMask: Shape {
    var crease: CGFloat
    let peeled: Bool

    var animatableData: CGFloat {
        get { crease }
        set { crease = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let corners = [CGPoint(x: 0, y: 0), CGPoint(x: rect.width, y: 0),
                       CGPoint(x: rect.width, y: rect.height), CGPoint(x: 0, y: rect.height)]
        // > 0 means "inside" the kept region
        func side(_ p: CGPoint) -> CGFloat { peeled ? (p.x + p.y - crease) : (crease - (p.x + p.y)) }
        var polygon: [CGPoint] = []
        for i in 0..<corners.count {
            let a = corners[i], b = corners[(i + 1) % corners.count]
            let sa = side(a), sb = side(b)
            if sa >= 0 { polygon.append(a) }
            if (sa >= 0) != (sb >= 0) {
                let t = sa / (sa - sb)
                polygon.append(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
            }
        }
        var path = Path()
        if polygon.count >= 3 {
            path.addLines(polygon)
            path.closeSubpath()
        }
        return path
    }
}

/// Reflects content across the line x + y = crease: (x, y) → (crease − y, crease − x).
private struct MirrorAcrossCrease: GeometryEffect {
    var crease: CGFloat

    var animatableData: CGFloat {
        get { crease }
        set { crease = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(a: 0, b: -1, c: -1, d: 0, tx: crease, ty: crease))
    }
}
