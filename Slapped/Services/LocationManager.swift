import CoreLocation

enum LocationError: LocalizedError {
    case denied

    var errorDescription: String? {
        "Location access is off. Enable it in Settings to log stickers."
    }
}

final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationManager()

    @Published private(set) var lastLocation: CLLocation?
    @Published private(set) var status: CLAuthorizationStatus = .notDetermined

    private let manager = CLLocationManager()
    private var waiters: [CheckedContinuation<CLLocation, Error>] = []

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        status = manager.authorizationStatus
    }

    func requestPermission() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    /// A fresh, reasonably accurate fix. Re-uses one from the last 20 seconds.
    func currentLocation() async throws -> CLLocation {
        if let last = lastLocation, -last.timestamp.timeIntervalSinceNow < 20, last.horizontalAccuracy <= 65 {
            return last
        }
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.main.async {
                self.waiters.append(continuation)
                switch self.manager.authorizationStatus {
                case .notDetermined: self.manager.requestWhenInUseAuthorization()
                case .denied, .restricted: self.finish(.failure(LocationError.denied))
                default: self.manager.requestLocation()
                }
            }
        }
    }

    static func placeName(for location: CLLocation) async -> String? {
        guard let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first else { return nil }
        let spot = placemark.areasOfInterest?.first ?? placemark.thoroughfare ?? placemark.name
        let parts = [spot, placemark.locality].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    // MARK: CLLocationManagerDelegate (delivered on the main thread)

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        status = manager.authorizationStatus
        guard !waiters.isEmpty else { return }
        switch status {
        case .authorizedWhenInUse, .authorizedAlways: manager.requestLocation()
        case .denied, .restricted: finish(.failure(LocationError.denied))
        default: break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        lastLocation = location
        finish(.success(location))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(.failure(error))
    }

    private func finish(_ result: Result<CLLocation, Error>) {
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume(with: result) }
    }
}
