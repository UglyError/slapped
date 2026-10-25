import SwiftUI
import PhotosUI
import MapKit

struct ScanView: View {
    var onFinished: () -> Void

    private enum Stage { case start, processing, review, details, checking, saving, done }

    @Environment(AppState.self) private var app
    @State private var stage: Stage = .start
    @State private var original: UIImage?
    @State private var cutout: UIImage?
    @State private var useOriginal = false
    @State private var showCamera = false
    @State private var photoItem: PhotosPickerItem?

    @State private var name = ""
    @State private var notes = ""
    @State private var location: CLLocation?
    @State private var placeName = ""
    @State private var locationError: String?
    @State private var errorMessage: String?
    @State private var saved: StickerCard?
    @State private var lookalike: DuplicateDetector.Match?

    private var finalImage: UIImage? { useOriginal ? original : (cutout ?? original) }

    var body: some View {
        NavigationStack {
            Group {
                switch stage {
                case .start: startView
                case .processing: progressView("Peeling it off the wall…")
                case .checking: progressView("Checking it's not already logged…")
                case .review: reviewView
                case .details, .saving: detailsView
                case .done: doneView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.bg)
            .navigationTitle(stage == .start ? "Scan" : "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if stage != .start && stage != .done && stage != .saving {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", action: reset)
                    }
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { image in Task { await process(image) } }
                    .ignoresSafeArea()
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                        await process(image)
                    }
                    photoItem = nil
                }
            }
            .alert("Can't log this one", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .sheet(item: Binding(get: { lookalike.map(LookalikeItem.init) }, set: { if $0 == nil { lookalike = nil } })) { item in
                LookalikeSheet(match: item.match, newImage: finalImage) { same in
                    lookalike = nil
                    if same {
                        errorMessage = APIError.alreadyLogged(name: item.match.sticker.name, by: item.match.sticker.finderUsername).localizedDescription
                    } else {
                        Task { await save(skipLookalikeCheck: true) }
                    }
                }
                .presentationDetents([.medium, .large])
            }
            .withRoutes()
        }
    }

    // MARK: Stages

    private var startView: some View {
        VStack(spacing: 24) {
            Spacer()
            ZStack {
                Circle().fill(Color.brand.opacity(0.15)).frame(width: 220, height: 220)
                Circle().fill(Color.brand).frame(width: 150, height: 150)
                Image(systemName: "viewfinder")
                    .font(.system(size: 64, weight: .bold))
                    .foregroundStyle(Color.onBrand)
            }
            .onTapGesture { showCamera = true }

            VStack(spacing: 6) {
                Text("Spotted a sticker?").font(.title2.weight(.heavy))
                Text("Fill the frame with the sticker and snap it. We'll cut it out, fix the lighting and angle, and tag where you found it.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)
            Spacer()
            VStack(spacing: 12) {
                Button { showCamera = true } label: { Label("Scan sticker", systemImage: "camera.fill") }
                    .buttonStyle(BrandButtonStyle())
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label("Choose from photos", systemImage: "photo.on.rectangle")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.cardRaised, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(24)
        }
    }

    private func progressView(_ text: String) -> some View {
        VStack(spacing: 16) {
            ProgressView().controlSize(.large)
            Text(text).font(.headline).foregroundStyle(.secondary)
        }
    }

    private var reviewView: some View {
        VStack(spacing: 20) {
            ZStack {
                Checkerboard()
                if let finalImage {
                    Image(uiImage: finalImage)
                        .resizable()
                        .scaledToFit()
                        .shadow(color: .black.opacity(0.3), radius: 12, y: 8)
                        .padding(24)
                }
            }
            .frame(maxHeight: .infinity)
            .card()

            if cutout == nil {
                Label("Couldn't isolate the sticker, so the full photo will be used. Try getting closer with a plain background.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Toggle("Use full photo instead of cutout", isOn: $useOriginal.animation())
                    .font(.subheadline)
                    .tint(.brand)
            }

            HStack(spacing: 12) {
                Button("Retake") { reset(); showCamera = true }
                    .buttonStyle(BrandButtonStyle(filled: false))
                Button("Looks good") { withAnimation { stage = .details } }
                    .buttonStyle(BrandButtonStyle())
            }
        }
        .padding()
    }

    private var detailsView: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let finalImage {
                    Image(uiImage: finalImage)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 180)
                        .shadow(color: .black.opacity(0.25), radius: 10, y: 6)
                        .padding(.vertical, 8)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("NAME").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                    TextField("What's on it?", text: $name)
                        .font(.title3.weight(.semibold))
                    Divider()
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(1...4)
                }
                .padding()
                .card()

                locationCard

                Button {
                    Task { await save() }
                } label: {
                    if stage == .saving {
                        ProgressView().tint(.onBrand)
                    } else {
                        Label("Log sticker", systemImage: "checkmark.seal.fill")
                    }
                }
                .buttonStyle(BrandButtonStyle())
                .disabled(!canSave)
                .opacity(canSave ? 1 : 0.5)
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        .disabled(stage == .saving)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && location != nil && stage == .details
    }

    private var locationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("FOUND AT").font(.caption.weight(.bold)).foregroundStyle(.secondary)
            if let location {
                Map(initialPosition: .camera(MapCamera(centerCoordinate: location.coordinate, distance: 600)),
                    interactionModes: []) {
                    Marker("", systemImage: "seal.fill", coordinate: location.coordinate).tint(Color.brand)
                }
                .frame(height: 140)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                TextField("Spot name", text: $placeName)
                    .font(.subheadline.weight(.semibold))
            } else if let locationError {
                Label(locationError, systemImage: "location.slash.fill").font(.subheadline).foregroundStyle(.secondary)
                Button("Try again") { Task { await fetchLocation() } }.font(.subheadline.weight(.semibold))
            } else {
                HStack { ProgressView(); Text("Getting your location…").foregroundStyle(.secondary) }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var doneView: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("Slapped!").font(.system(size: 40, weight: .black, design: .rounded))
            if let saved {
                StickerArtwork(url: saved.imageURL)
                    .frame(width: 240, height: 240)
                Text(saved.name).font(.title2.weight(.bold))
                HStack {
                    Text("Added to your collection")
                    ValueChip(value: saved.value)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(spacing: 12) {
                if let saved {
                    NavigationLink(value: Route.sticker(saved)) {
                        Text("View sticker").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(Color.cardRaised, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Button("Scan another") { reset() }
                    .buttonStyle(BrandButtonStyle())
                Button("Back to feed") { reset(); onFinished() }
                    .font(.subheadline.weight(.semibold))
            }
            .padding(24)
        }
        .sensoryFeedback(.success, trigger: saved?.id)
    }

    // MARK: Actions

    private func process(_ image: UIImage) async {
        reset()
        stage = .processing
        original = image.resized(maxDimension: 1600)
        Task { await fetchLocation() }
        cutout = await StickerCutout.cutout(image)
        withAnimation { stage = .review }
    }

    private func fetchLocation() async {
        locationError = nil
        do {
            let fix = try await LocationManager.shared.currentLocation()
            location = fix
            if placeName.isEmpty, let name = await LocationManager.placeName(for: fix) {
                placeName = name
            }
        } catch {
            locationError = error.localizedDescription
        }
    }

    private func save(skipLookalikeCheck: Bool = false) async {
        guard let image = finalImage?.resized(maxDimension: 1024), let location else { return }
        do {
            if !skipLookalikeCheck {
                stage = .checking
                let nearby = (try? await API.nearby(location.coordinate, radius: 40, limit: 15)) ?? []
                if let match = await DuplicateDetector.closestMatch(for: image, among: nearby) {
                    if match.distance < DuplicateDetector.sameThreshold {
                        throw APIError.alreadyLogged(name: match.sticker.name, by: match.sticker.finderUsername)
                    }
                    if match.distance < DuplicateDetector.askThreshold {
                        stage = .details
                        lookalike = match
                        return
                    }
                }
            }
            stage = .saving
            let hashes = PerceptualHash.rotationHashes(image)
            // cheap check before uploading; the server re-checks atomically on create
            if try await API.isDuplicate(hashes: hashes, at: location.coordinate) {
                throw APIError.duplicateSticker
            }
            saved = try await API.createSticker(
                image: image,
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                details: notes,
                hashes: hashes,
                coordinate: location.coordinate,
                placeName: placeName
            )
            withAnimation { stage = .done }
            await app.refresh()
        } catch {
            errorMessage = error.localizedDescription
            stage = .details
        }
    }

    private func reset() {
        stage = .start
        original = nil
        cutout = nil
        useOriginal = false
        name = ""
        notes = ""
        location = nil
        placeName = ""
        locationError = nil
        saved = nil
    }
}

struct CameraPicker: UIViewControllerRepresentable {
    var onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker

        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

private struct LookalikeItem: Identifiable {
    let match: DuplicateDetector.Match
    var id: UUID { match.sticker.id }
}

/// Shown when a nearby sticker looks similar but not certainly the same.
private struct LookalikeSheet: View {
    let match: DuplicateDetector.Match
    let newImage: UIImage?
    let onAnswer: (_ same: Bool) -> Void

    var body: some View {
        VStack(spacing: 18) {
            Text("Is this the same sticker?").font(.title2.weight(.heavy))
            Text("“\(match.sticker.name)” by @\(match.sticker.finderUsername) was logged right here.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            HStack(spacing: 12) {
                VStack {
                    StickerArtwork(url: match.sticker.imageURL, padding: 10).frame(height: 150)
                    Text("Already logged").font(.caption.weight(.semibold))
                }
                VStack {
                    ZStack {
                        Checkerboard()
                        if let newImage { Image(uiImage: newImage).resizable().scaledToFit().padding(10) }
                    }
                    .frame(height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    Text("Your scan").font(.caption.weight(.semibold))
                }
            }
            HStack(spacing: 12) {
                Button("Same sticker") { onAnswer(true) }.buttonStyle(BrandButtonStyle(filled: false))
                Button("It's different") { onAnswer(false) }.buttonStyle(BrandButtonStyle())
            }
        }
        .padding(24)
    }
}
