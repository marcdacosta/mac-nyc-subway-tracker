import Foundation
import NostrandCore

enum TravelDirection: String, CaseIterable, Identifiable {
    case northbound
    case southbound

    var id: String { rawValue }
    var title: String { self == .northbound ? "Northbound" : "Southbound" }
    var isNorthbound: Bool { self == .northbound }
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
    @Published private(set) var selectedStation: SubwayStation
    @Published private(set) var routeFilterID: String?
    @Published private(set) var direction: TravelDirection
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
    }

    init(
        client: TransiterClient = TransiterClient(),
        defaults: UserDefaults = .standard
    ) {
        self.client = client
        self.defaults = defaults

        if let data = defaults.data(forKey: DefaultsKey.station),
           let savedStation = try? JSONDecoder().decode(SubwayStation.self, from: data) {
            selectedStation = savedStation
        } else {
            selectedStation = .nostrandAvenue
        }

        if defaults.object(forKey: DefaultsKey.route) == nil {
            routeFilterID = "A"
        } else {
            let savedRoute = defaults.string(forKey: DefaultsKey.route)
            routeFilterID = savedRoute == "*" ? nil : savedRoute
        }

        direction = TravelDirection(
            rawValue: defaults.string(forKey: DefaultsKey.direction) ?? "northbound"
        ) ?? .northbound
    }

    deinit {
        refreshTask?.cancel()
    }

    func start() async {
        refresh()
        await loadStations()
    }

    func refresh() {
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
                      self.selectedStation.id == requestedStationID,
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

            if let canonicalStation = stations.first(where: { $0.id == selectedStation.id }) {
                selectedStation = canonicalStation
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

    func selectStation(_ station: SubwayStation) {
        let isNewStation = station.id != selectedStation.id
        selectedStation = station
        if isNewStation {
            routeFilterID = nil
        }
        persistSelection()
        refresh()
    }

    func selectRoute(_ routeID: String?) {
        routeFilterID = routeID
        persistSelection()
        refresh()
    }

    func selectDirection(_ newDirection: TravelDirection) {
        direction = newDirection
        persistSelection()
        refresh()
    }

    func applyLocation(latitude: Double, longitude: Double, horizontalAccuracy: Double) {
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

        selectStation(nearest.station)

        if let second = nearbyStations.dropFirst().first,
           horizontalAccuracy > max(100, (second.distanceInMeters - nearest.distanceInMeters) / 2) {
            locationMessage = "Location is approximate. Check the nearby alternatives below."
        } else {
            locationMessage = "Selected the nearest station."
        }
    }

    func setLocationError(_ message: String) {
        locationMessage = message
    }

    private func persistSelection() {
        if let data = try? JSONEncoder().encode(selectedStation) {
            defaults.set(data, forKey: DefaultsKey.station)
        }
        defaults.set(routeFilterID ?? "*", forKey: DefaultsKey.route)
        defaults.set(direction.rawValue, forKey: DefaultsKey.direction)
    }
}
