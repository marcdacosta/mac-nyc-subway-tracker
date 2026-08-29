import CoreLocation
import Foundation

@MainActor
final class LocationProvider: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    @Published private(set) var isLocating = false

    private let manager: CLLocationManager
    private var completion: ((Result<CLLocation, Error>) -> Void)?

    override init() {
        manager = CLLocationManager()
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func requestLocation(completion: @escaping (Result<CLLocation, Error>) -> Void) {
        guard !isLocating else { return }

        guard CLLocationManager.locationServicesEnabled() else {
            completion(.failure(LocationProviderError.servicesDisabled))
            return
        }

        isLocating = true
        self.completion = completion

        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .denied:
            finish(.failure(LocationProviderError.permissionDenied))
        case .restricted:
            finish(.failure(LocationProviderError.permissionRestricted))
        @unknown default:
            finish(.failure(LocationProviderError.unavailable))
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard isLocating else { return }

        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .denied:
            finish(.failure(LocationProviderError.permissionDenied))
        case .restricted:
            finish(.failure(LocationProviderError.permissionRestricted))
        case .notDetermined:
            break
        @unknown default:
            finish(.failure(LocationProviderError.unavailable))
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations
            .filter({ $0.horizontalAccuracy >= 0 })
            .max(by: { $0.timestamp < $1.timestamp })
        else {
            finish(.failure(LocationProviderError.unavailable))
            return
        }

        finish(.success(location))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(.failure(error))
    }

    private func finish(_ result: Result<CLLocation, Error>) {
        let callback = completion
        completion = nil
        isLocating = false
        callback?(result)
    }
}

private enum LocationProviderError: LocalizedError {
    case servicesDisabled
    case permissionDenied
    case permissionRestricted
    case unavailable

    var errorDescription: String? {
        switch self {
        case .servicesDisabled:
            "Location Services are turned off in System Settings."
        case .permissionDenied:
            "Location access was denied. You can enable it in Privacy & Security settings."
        case .permissionRestricted:
            "Location access is restricted on this Mac."
        case .unavailable:
            "Your Mac could not determine its current location."
        }
    }
}
