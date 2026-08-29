import SwiftUI

@main
struct MacNYCSubwayTrackerApp: App {
    @StateObject private var store = ArrivalStore()
    @StateObject private var locationProvider = LocationProvider()
    @State private var hasStarted = false

    var body: some Scene {
        MenuBarExtra {
            ArrivalsMenuView(
                store: store,
                locationProvider: locationProvider
            )
        } label: {
            Image(nsImage: StatusBarIcon.image(routeID: store.routeFilterID))
                .renderingMode(.original)
                .resizable()
                .interpolation(.high)
                .frame(width: 18, height: 18)
                .accessibilityLabel(statusIconAccessibilityLabel)
                .id(store.routeFilterID ?? "all-trains")
                .task {
                    guard !hasStarted else { return }
                    hasStarted = true
                    await store.start()
                    synchronizeLocationMode()
                }
                .onChange(of: store.stationSelectionMode) { _ in
                    synchronizeLocationMode()
                }
                .onChange(of: store.stations.count) { _ in
                    synchronizeLocationMode()
                }
        }
        .menuBarExtraStyle(.window)
    }

    private var statusIconAccessibilityLabel: String {
        store.routeFilterID.map { "\($0) train times" } ?? "All train times"
    }

    private func synchronizeLocationMode() {
        guard store.stationSelectionMode == .automatic else {
            locationProvider.stopMonitoring()
            return
        }

        guard !store.stations.isEmpty else {
            if let stationLoadError = store.stationLoadError {
                store.setLocationError(stationLoadError)
            }
            return
        }

        locationProvider.startMonitoring { [weak store] location in
            store?.applyLocation(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                horizontalAccuracy: location.horizontalAccuracy
            )
        } onError: { [weak store] error in
            store?.setLocationError(error.localizedDescription)
        }
    }
}
