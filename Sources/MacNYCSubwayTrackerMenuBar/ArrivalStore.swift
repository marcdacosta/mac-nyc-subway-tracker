import Foundation
import MacNYCSubwayTrackerCore

enum TravelDirection: String, CaseIterable, Identifiable {
    case northbound
    case southbound

    var id: String { rawValue }
    var title: String { self == .northbound ? "Northbound" : "Southbound" }
    var isNorthbound: Bool { self == .northbound }
}

enum StationSelectionMode: String, CaseIterable, Identifiable {
    case automatic
    case home

    var id: String { rawValue }
    var title: String { self == .automatic ? "Automatic" : "Home station" }
}

@MainActor
final class ArrivalStore: ObservableObject {
    @Published private(set) var arrivals: [Arrival] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastUpdated: Date?

    @Published private(set) var stations: [SubwayStation] = []
    @Published private(set) var isLoadingStations = false
    @Published private(set) var stationLoadError: String?
    @Published private(set) var selectedStation: SubwayStation?
    @Published private(set) var routeFilterID: String?
    @Published private(set) var direction: TravelDirection
    @Published private(set) var stationSelectionMode: StationSelectionMode?
    @Published private(set) var nearbyStations: [NearbyStation] = []
    @Published private(set) var locationMessage: String?
    @Published private(set) var locationAccuracy: Double?

    private let client: TransiterClient
    private let defaults: UserDefaults
    private var refreshTask: Task<Void, Never>?

    private enum DefaultsKey {
        static let station = "selectedStation"
        static let route = "selectedRoute"
        static let direction = "selectedDirection"
        static let stationSelectionMode = "stationSelectionMode"
    }

    var needsSetup: Bool {
        stationSelectionMode == nil
            || (stationSelectionMode == .home && selectedStation == nil)
    }

    init(
        client: TransiterClient = TransiterClient(),
        defaults: UserDefaults = .standard
    ) {
        self.client = client
        self.defaults = defaults

        if let data = defaults.data(forKey: DefaultsKey.station) {
            selectedStation = try? JSONDecoder().decode(SubwayStation.self, from: data)
        } else {
            selectedStation = nil
        }

        routeFilterID = defaults.string(forKey: DefaultsKey.route).flatMap {
            $0 == "*" ? nil : $0
        }

        direction = TravelDirection(
            rawValue: defaults.string(forKey: DefaultsKey.direction) ?? "northbound"
        ) ?? .northbound

        let savedMode = defaults.string(forKey: DefaultsKey.stationSelectionMode)
            .flatMap(StationSelectionMode.init(rawValue:))
        stationSelectionMode = savedMode == .home && selectedStation == nil ? nil : savedMode
    }

    deinit {
        refreshTask?.cancel()
    }

    func start() async {
        if !needsSetup, selectedStation != nil {
            refresh()
        }
        await loadStations()
    }

    func refresh() {
        guard !needsSetup, let selectedStation else {
            refreshTask?.cancel()
            arrivals = []
            isLoading = false
            return
        }

        refreshTask?.cancel()
        isLoading = true

        let requestedStationID = selectedStation.id
        let requestedRouteID = routeFilterID
        let requestedDirection = direction
        let client = client

        refreshTask = Task { [weak self] in
            do {
                let result = try await client.fetchArrivals(
                    stationID: requestedStationID,
                    routeID: requestedRouteID,
                    northbound: requestedDirection.isNorthbound
                )
                try Task.checkCancellation()

                guard let self,
                      self.selectedStation?.id == requestedStationID,
                      self.routeFilterID == requestedRouteID,
                      self.direction == requestedDirection
                else {
                    return
                }

                self.arrivals = result
                self.errorMessage = nil
                self.lastUpdated = .now
                self.isLoading = false
            } catch is CancellationError {
                return
            } catch {
                guard let self else { return }
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    func loadStations() async {
        guard stations.isEmpty, !isLoadingStations else { return }

        isLoadingStations = true
        stationLoadError = nil
        defer { isLoadingStations = false }

        do {
            stations = try await client.fetchStations()

            if let selectedStation,
               let canonicalStation = stations.first(where: { $0.id == selectedStation.id }) {
                self.selectedStation = canonicalStation
                if let routeFilterID,
                   !canonicalStation.routes.contains(where: { $0.id == routeFilterID }) {
                    self.routeFilterID = nil
                }
                persistSelection()
            }
        } catch is CancellationError {
            return
        } catch {
            stationLoadError = error.localizedDescription
        }
    }

    func enableAutomaticStationSelection() {
        stationSelectionMode = .automatic
        routeFilterID = nil
        locationMessage = "Finding the nearest station…"
        persistSelection()

        if selectedStation != nil {
            refresh()
        }
    }

    func keepCurrentStationAsHome() {
        guard selectedStation != nil else {
            clearStationSelection()
            return
        }

        stationSelectionMode = .home
        locationMessage = nil
        locationAccuracy = nil
        nearbyStations = []
        persistSelection()
    }

    func selectHomeStation(_ station: SubwayStation) {
        stationSelectionMode = .home
        locationMessage = nil
        locationAccuracy = nil
        nearbyStations = []
        selectStation(station)
    }

    func clearStationSelection() {
        refreshTask?.cancel()
        stationSelectionMode = nil
        selectedStation = nil
        routeFilterID = nil
        arrivals = []
        isLoading = false
        errorMessage = nil
        locationMessage = nil
        locationAccuracy = nil
        nearbyStations = []
        persistSelection()
    }

    func selectRoute(_ routeID: String?) {
        guard selectedStation != nil else { return }
        routeFilterID = routeID
        persistSelection()
        refresh()
    }

    func selectDirection(_ newDirection: TravelDirection) {
        guard selectedStation != nil else { return }
        direction = newDirection
        persistSelection()
        refresh()
    }

    func applyLocation(latitude: Double, longitude: Double, horizontalAccuracy: Double) {
        guard stationSelectionMode == .automatic else { return }

        locationAccuracy = horizontalAccuracy >= 0 ? horizontalAccuracy : nil
        nearbyStations = stations.nearest(
            latitude: latitude,
            longitude: longitude,
            limit: 8
        )

        guard let nearest = nearbyStations.first else {
            locationMessage = "No subway stations were available for this location."
            return
        }

        let stationChanged = nearest.station.id != selectedStation?.id
        selectStation(nearest.station)

        if let second = nearbyStations.dropFirst().first,
           horizontalAccuracy > max(100, (second.distanceInMeters - nearest.distanceInMeters) / 2) {
            locationMessage = "Location is approximate. Check the nearby alternatives below."
        } else if stationChanged {
            locationMessage = "Now following the nearest station."
        } else {
            locationMessage = "Automatic location is on."
        }
    }

    func setLocationError(_ message: String) {
        locationMessage = message
    }

    private func selectStation(_ station: SubwayStation) {
        let isNewStation = station.id != selectedStation?.id
        selectedStation = station
        if isNewStation {
            routeFilterID = nil
        }
        persistSelection()

        if isNewStation || arrivals.isEmpty {
            refresh()
        }
    }

    private func persistSelection() {
        if let selectedStation,
           let data = try? JSONEncoder().encode(selectedStation) {
            defaults.set(data, forKey: DefaultsKey.station)
        } else {
            defaults.removeObject(forKey: DefaultsKey.station)
        }

        if let stationSelectionMode {
            defaults.set(stationSelectionMode.rawValue, forKey: DefaultsKey.stationSelectionMode)
        } else {
            defaults.removeObject(forKey: DefaultsKey.stationSelectionMode)
        }

        defaults.set(routeFilterID ?? "*", forKey: DefaultsKey.route)
        defaults.set(direction.rawValue, forKey: DefaultsKey.direction)
    }
}
