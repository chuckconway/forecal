import CoreLocation
import Foundation

/// The Mac's location, shared by the weather forecast and drive times.
@MainActor
final class LocationStore: NSObject, ObservableObject {
    @Published private(set) var location: CLLocation?

    private static let savedKey = "lastCoordinate"
    private let manager = CLLocationManager()
    private var timer: Timer?

    override init() {
        super.init()
        // Start from the last known location so weather and drive times show immediately.
        if let saved = UserDefaults.standard.array(forKey: Self.savedKey) as? [Double], saved.count == 2 {
            location = CLLocation(latitude: saved[0], longitude: saved[1])
        }
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        refresh()

        // Drive times go stale when the Mac moves, so check more often than the weather needs.
        timer = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        timer?.tolerance = 60
    }

    func refresh() {
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .denied, .restricted: break
        default: manager.requestLocation()
        }
    }

    private func update(_ new: CLLocation) {
        // Wi-Fi fixes jitter; only publish real moves so dependents don't refetch.
        if let location, location.distance(from: new) < 200 { return }
        location = new
        UserDefaults.standard.set([new.coordinate.latitude, new.coordinate.longitude], forKey: Self.savedKey)
    }
}

extension LocationStore: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.refresh() }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in self.update(location) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        NSLog("ForeCal: location failed: \(error)")
    }
}
