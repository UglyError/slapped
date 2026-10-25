import SwiftUI
import AVFoundation
import PhotosUI

/// Full-screen sticker camera: viewfinder, tap to focus, flash, shutter, photo library.
struct CameraScreen: View {
    let onImage: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @StateObject private var camera = CameraModel()
    @State private var photoItem: PhotosPickerItem?
    @State private var flashOverlay = false
    @State private var focusPoint: CGPoint?
    @State private var shots = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if camera.denied {
                deniedView
            } else {
                CameraPreview(session: camera.session) { layerPoint, devicePoint in
                    camera.focus(at: devicePoint)
                    focusPoint = layerPoint
                }
                .ignoresSafeArea()
                viewfinder
                if let focusPoint {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.brand, lineWidth: 2)
                        .frame(width: 70, height: 70)
                        .position(focusPoint)
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }
            }

            Color.white.opacity(flashOverlay ? 0.85 : 0).ignoresSafeArea().allowsHitTesting(false)

            VStack {
                topBar
                Spacer()
                bottomBar
            }
        }
        .statusBarHidden()
        .onAppear { camera.start() }
        .onDisappear { camera.stop() }
        .onChange(of: focusPoint) { _, point in
            guard point != nil else { return }
            Task {
                try? await Task.sleep(for: .seconds(1.2))
                withAnimation { focusPoint = nil }
            }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    finish(with: image)
                }
                photoItem = nil
            }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: shots)
    }

    private var viewfinder: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height) * 0.72
            ZStack {
                ViewfinderBrackets()
                    .stroke(Color.brand, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                    .frame(width: side, height: side)
                Text("Fill the frame with the sticker")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(.black.opacity(0.45), in: Capsule())
                    .offset(y: side / 2 + 30)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .allowsHitTesting(false)
    }

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.title3.weight(.bold))
                    .frame(width: 44, height: 44)
                    .background(.black.opacity(0.45), in: Circle())
            }
            .accessibilityLabel("Close")
            Spacer()
            Button { camera.flash = camera.flash == .off ? .on : .off } label: {
                Image(systemName: camera.flash == .on ? "bolt.fill" : "bolt.slash.fill")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(camera.flash == .on ? Color.brand : .white)
                    .frame(width: 44, height: 44)
                    .background(.black.opacity(0.45), in: Circle())
            }
            .accessibilityLabel(camera.flash == .on ? "Flash on" : "Flash off")
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private var bottomBar: some View {
        HStack {
            PhotosPicker(selection: $photoItem, matching: .images) {
                Image(systemName: "photo.on.rectangle")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 14))
            }
            .accessibilityLabel("Choose from photos")
            Spacer()
            Button(action: shoot) {
                ZStack {
                    Circle().stroke(.white, lineWidth: 5).frame(width: 82, height: 82)
                    Circle().fill(camera.isCapturing ? Color.brand.opacity(0.6) : Color.brand).frame(width: 66, height: 66)
                    Image(systemName: "viewfinder").font(.title2.weight(.bold)).foregroundStyle(Color.onBrand)
                }
            }
            .disabled(camera.isCapturing || !camera.isAvailable)
            .accessibilityLabel("Take photo")
            Spacer()
            Color.clear.frame(width: 56, height: 56)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 24)
    }

    private var deniedView: some View {
        VStack(spacing: 14) {
            Image(systemName: "camera.fill").font(.system(size: 44)).foregroundStyle(Color.brand)
            Text("Camera access is off").font(.headline).foregroundStyle(.white)
            Text("Allow camera access to scan stickers, or pick a photo instead.")
                .font(.subheadline).foregroundStyle(.white.opacity(0.7)).multilineTextAlignment(.center)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            .buttonStyle(BrandButtonStyle())
            .frame(maxWidth: 220)
        }
        .padding(32)
    }

    private func shoot() {
        shots += 1
        withAnimation(.easeOut(duration: 0.06)) { flashOverlay = true }
        withAnimation(.easeIn(duration: 0.25).delay(0.06)) { flashOverlay = false }
        camera.capture { image in
            if let image { finish(with: image) }
        }
    }

    private func finish(with image: UIImage) {
        onImage(image)
        dismiss()
    }
}

private struct ViewfinderBrackets: Shape {
    func path(in rect: CGRect) -> Path {
        let arm = rect.width * 0.18
        var path = Path()
        for (corner, dx, dy) in [(CGPoint(x: rect.minX, y: rect.minY), 1.0, 1.0),
                                 (CGPoint(x: rect.maxX, y: rect.minY), -1.0, 1.0),
                                 (CGPoint(x: rect.maxX, y: rect.maxY), -1.0, -1.0),
                                 (CGPoint(x: rect.minX, y: rect.maxY), 1.0, -1.0)] {
            path.move(to: CGPoint(x: corner.x, y: corner.y + dy * arm))
            path.addLine(to: corner)
            path.addLine(to: CGPoint(x: corner.x + dx * arm, y: corner.y))
        }
        return path
    }
}

/// Live camera preview; reports taps in view and device coordinates for focusing.
private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let onTap: (CGPoint, CGPoint) -> Void

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.addGestureRecognizer(UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:))))
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onTap: onTap) }

    final class Coordinator: NSObject {
        let onTap: (CGPoint, CGPoint) -> Void
        init(onTap: @escaping (CGPoint, CGPoint) -> Void) { self.onTap = onTap }

        @objc func tapped(_ recognizer: UITapGestureRecognizer) {
            guard let view = recognizer.view as? PreviewView else { return }
            let point = recognizer.location(in: view)
            onTap(point, view.previewLayer.captureDevicePointConverted(fromLayerPoint: point))
        }
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

final class CameraModel: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    @Published var flash: AVCaptureDevice.FlashMode = .off
    @Published var denied = false
    @Published var isCapturing = false
    @Published var isAvailable = true

    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "slapped.camera")
    private var device: AVCaptureDevice?
    private var completion: ((UIImage?) -> Void)?

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndRun()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted { self.configureAndRun() } else { DispatchQueue.main.async { self.denied = true } }
            }
        default:
            denied = true
        }
    }

    func stop() {
        queue.async { if self.session.isRunning { self.session.stopRunning() } }
    }

    private func configureAndRun() {
        queue.async {
            if self.session.inputs.isEmpty {
                self.session.beginConfiguration()
                self.session.sessionPreset = .photo
                if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                   let input = try? AVCaptureDeviceInput(device: device),
                   self.session.canAddInput(input) {
                    self.session.addInput(input)
                    self.device = device
                }
                if self.session.canAddOutput(self.output) {
                    self.session.addOutput(self.output)
                    self.output.maxPhotoQualityPrioritization = .quality
                }
                self.session.commitConfiguration()
                let available = self.device != nil
                DispatchQueue.main.async { self.isAvailable = available }
            }
            if self.device != nil && !self.session.isRunning { self.session.startRunning() }
        }
    }

    func focus(at devicePoint: CGPoint) {
        queue.async {
            guard let device = self.device, (try? device.lockForConfiguration()) != nil else { return }
            if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(.autoFocus) {
                device.focusPointOfInterest = devicePoint
                device.focusMode = .autoFocus
            }
            if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(.autoExpose) {
                device.exposurePointOfInterest = devicePoint
                device.exposureMode = .autoExpose
            }
            device.unlockForConfiguration()
        }
    }

    func capture(_ done: @escaping (UIImage?) -> Void) {
        guard device != nil else { done(nil); return }
        completion = done
        isCapturing = true
        let flashMode = flash
        queue.async {
            let settings = AVCapturePhotoSettings()
            if self.output.supportedFlashModes.contains(flashMode) { settings.flashMode = flashMode }
            settings.photoQualityPrioritization = .balanced
            if let connection = self.output.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90   // portrait
            }
            self.output.capturePhoto(with: settings, delegate: self)
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let image = photo.fileDataRepresentation().flatMap(UIImage.init(data:))
        DispatchQueue.main.async {
            self.isCapturing = false
            self.completion?(image)
            self.completion = nil
        }
    }
}
