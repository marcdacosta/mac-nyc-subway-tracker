import CoreLocation
import Foundation

@MainActor
final class LocationProvider: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    @Published private(set) var isLocating = false
    @Published private(set) var isMonitoring = false

    private let manager: CLLocationManager
    private var locationHandler: ((CLLocation) -> Void)?
    private var errorHandler: ((Error) -> Void)?

    override init() {
        manager = CLLocationManager()
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 200
    }

    func startMonitoring(
        onLocation: @escaping (CLLocation) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        locationHandler = onLocation
        errorHandler = onError

        guard CLLocationManager.locationServicesEnabled() else {
            stopMonitoring()
            onError(LocationProviderError.servicesDisabled)
            return
        }

        guard !isMonitoring, !isLocating else { return }

        switch manager.authorizationStatus {
        case .notDetermined:
            isLocating = true
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            beginUpdates()
        case .denied:
            stopMonitoring()
            onError(LocationProviderError.permissionDenied)
        case .restricted:
            stopMonitoring()
            onError(LocationProviderError.permissionRestricted)
        @unknown default:
            stopMonitoring()
            onError(LocationProviderError.unavailable)
        }
    }

    func stopMonitoring() {
        manager.stopUpdatingLocation()
        isMonitoring = false
        isLocating = false
        locationHandler = nil
        errorHandler = nil
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard locationHandler != nil else { return }

        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            beginUpdates()
        case .denied:
            reportTerminalError(.permissionDenied)
        case .restricted:
            reportTerminalError(.permissionRestricted)
        case .notDetermined:
            break
        @unknown default:
            reportTerminalError(.unavailable)
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations
            .filter({ $0.horizontalAccuracy >= 0 })
            .max(by: { $0.timestamp < $1.timestamp })
        else {
            errorHandler?(LocationProviderError.unavailable)
            return
        }

        isLocating = false
        locationHandler?(location)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let coreLocationError = error as? CLError,
           coreLocationError.code == .locationUnknown {
            isLocating = true
            errorHandler?(LocationProviderError.temporarilyUnavailable)
            return
        }

        isLocating = false
        errorHandler?(error)
    }

    private func beginUpdates() {
        isMonitoring = true
        isLocating = true
        manager.startUpdatingLocation()
    }

    private func reportTerminalError(_ error: LocationProviderError) {
        let callback = errorHandler
        stopMonitoring()
        callback?(error)
    }
}

private enum LocationProviderError: LocalizedError {
    case servicesDisabled
    case permissionDenied
    case permissionRestricted
    case temporarilyUnavailable
    case unavailable

    var errorDescription: String? {
        switch self {
        case .servicesDisabled:
            "Location Services are turned off in System Settings."
        case .permissionDenied:
            "Location access was denied. Enable it in Privacy & Security settings, or choose a home station."
        case .permissionRestricted:
            "Location access is restricted on this Mac. Choose a home station instead."
        case .temporarilyUnavailable:
            "Waiting for a more accurate location from this Mac."
        case .unavailable:
            "Your Mac could not determine its current location."
        }
    }
}
