import SwiftUI

/// Hand-made cut-out for when the automatic one misses: trace around the sticker,
/// or drag four corners for rectangular stickers (flattened to face-on).
struct ManualCutoutView: View {
    let image: UIImage
    let onDone: (UIImage) -> Void

    private enum Tool: String, CaseIterable { case trace = "Trace", corners = "Corners" }

    @Environment(\.dismiss) private var dismiss
    @State private var tool: Tool = .trace
    @State private var trace: [CGPoint] = []          // image pixels
    @State private var drawing = false
    @State private var corners: [CGPoint] = []        // image pixels: TL, TR, BR, BL
    @State private var dragging: Int?
    @State private var working = false
    @State private var failed = false

    private var canCut: Bool {
        switch tool {
        case .trace: trace.count >= 12 && !drawing
        case .corners: corners.count == 4
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                Picker("Tool", selection: $tool) {
                    ForEach(Tool.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                Text(tool == .trace
                     ? "Draw around the edge of the sticker with your finger."
                     : "Drag the corners onto the corners of the sticker.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                GeometryReader { geo in
                    let frame = fittedRect(in: geo.size)
                    ZStack(alignment: .topLeading) {
                        Image(uiImage: image)
                            .resizable()
                            .frame(width: frame.width, height: frame.height)
                            .offset(x: frame.minX, y: frame.minY)
                        overlay(in: frame)
                    }
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                    .contentShape(Rectangle())
                    .gesture(tool == .trace ? traceGesture(in: frame) : nil)
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                if failed {
                    Text("Couldn't cut that out. Try again.").font(.footnote).foregroundStyle(.red)
                }

                HStack(spacing: 12) {
                    Button(tool == .trace ? "Clear" : "Reset") { reset() }
                        .buttonStyle(BrandButtonStyle(filled: false))
                    Button {
                        Task { await cut() }
                    } label: {
                        if working { ProgressView().tint(.onBrand) } else { Text("Cut out") }
                    }
                    .buttonStyle(BrandButtonStyle())
                    .disabled(!canCut || working)
                    .opacity(canCut ? 1 : 0.5)
                }
            }
            .padding()
            .background(Color.bg)
            .navigationTitle("Manual cut-out")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .task { await placeCorners() }
        }
    }

    // MARK: Drawing

    @ViewBuilder
    private func overlay(in frame: CGRect) -> some View {
        switch tool {
        case .trace:
            let points = trace.map { toView($0, frame) }
            Path { path in
                guard let first = points.first else { return }
                path.move(to: first)
                path.addLines(Array(points.dropFirst()))
                if !drawing { path.closeSubpath() }
            }
            .fill(drawing ? Color.clear : Color.brand.opacity(0.2))
            .overlay(
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: first)
                    path.addLines(Array(points.dropFirst()))
                    if !drawing { path.closeSubpath() }
                }
                .stroke(Color.brand, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round, dash: drawing ? [] : [8, 5]))
            )
            .allowsHitTesting(false)
        case .corners:
            let points = corners.map { toView($0, frame) }
            Path { path in
                guard points.count == 4 else { return }
                path.addLines(points)
                path.closeSubpath()
            }
            .fill(Color.brand.opacity(0.18))
            .overlay(Path { path in
                guard points.count == 4 else { return }
                path.addLines(points)
                path.closeSubpath()
            }.stroke(Color.brand, lineWidth: 2.5))
            .allowsHitTesting(false)
            ForEach(points.indices, id: \.self) { index in
                Circle()
                    .fill(Color.brand)
                    .overlay(Circle().stroke(.white, lineWidth: 3))
                    .frame(width: dragging == index ? 34 : 28, height: dragging == index ? 34 : 28)
                    .shadow(radius: 3)
                    .frame(width: 56, height: 56)          // bigger touch target
                    .contentShape(Circle())
                    .position(points[index])
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            dragging = index
                            corners[index] = toImage(clamped(value.location, to: frame), frame)
                        }
                        .onEnded { _ in dragging = nil })
            }
        }
    }

    private func traceGesture(in frame: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !drawing { trace = []; drawing = true; failed = false }
                let point = toImage(clamped(value.location, to: frame), frame)
                // skip points closer than ~4 screen points to keep the path light
                if let last = trace.last, hypot(point.x - last.x, point.y - last.y) < 4 * scale(frame) { return }
                trace.append(point)
            }
            .onEnded { _ in drawing = false }
    }

    // MARK: Geometry (view points ↔ image pixels)

    private func fittedRect(in container: CGSize) -> CGRect {
        let ratio = min(container.width / image.size.width, container.height / image.size.height)
        let size = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
        return CGRect(x: (container.width - size.width) / 2, y: (container.height - size.height) / 2,
                      width: size.width, height: size.height)
    }

    private func scale(_ frame: CGRect) -> CGFloat { image.size.width / frame.width }

    private func toImage(_ p: CGPoint, _ frame: CGRect) -> CGPoint {
        CGPoint(x: (p.x - frame.minX) * scale(frame), y: (p.y - frame.minY) * scale(frame))
    }

    private func toView(_ p: CGPoint, _ frame: CGRect) -> CGPoint {
        CGPoint(x: frame.minX + p.x / scale(frame), y: frame.minY + p.y / scale(frame))
    }

    private func clamped(_ p: CGPoint, to frame: CGRect) -> CGPoint {
        CGPoint(x: min(max(p.x, frame.minX), frame.maxX), y: min(max(p.y, frame.minY), frame.maxY))
    }

    // MARK: Actions

    private func defaultCorners() -> [CGPoint] {
        let w = image.size.width, h = image.size.height
        return [CGPoint(x: w * 0.2, y: h * 0.25), CGPoint(x: w * 0.8, y: h * 0.25),
                CGPoint(x: w * 0.8, y: h * 0.75), CGPoint(x: w * 0.2, y: h * 0.75)]
    }

    private func placeCorners() async {
        corners = defaultCorners()
        if let detected = await StickerCutout.detectedCorners(in: image) { corners = detected }
    }

    private func reset() {
        failed = false
        switch tool {
        case .trace: trace = []
        case .corners: Task { await placeCorners() }
        }
    }

    private func cut() async {
        working = true
        failed = false
        let result: UIImage? = switch tool {
        case .trace: await StickerCutout.cutout(image, tracing: trace)
        case .corners: await StickerCutout.cutout(image, corners: corners)
        }
        working = false
        if let result {
            onDone(result)
            dismiss()
        } else {
            failed = true
        }
    }
}
