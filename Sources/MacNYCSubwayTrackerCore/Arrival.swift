import Foundation

public struct Arrival: Identifiable, Equatable, Sendable {
    public let id: String
    public let routeID: String
    public let routeColor: String?
    public let destination: String
    public let time: Date

    public init(
        id: String,
        routeID: String,
        routeColor: String?,
        destination: String,
        time: Date
    ) {
        self.id = id
        self.routeID = routeID
        self.routeColor = routeColor
        self.destination = destination
        self.time = time
    }
}

public struct SubwayRoute: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let color: String?

    public init(id: String, color: String?) {
        self.id = id
        self.color = color
    }
}

public struct SubwayStation: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let latitude: Double
    public let longitude: Double
    public let routes: [SubwayRoute]

    public init(
        id: String,
        name: String,
        latitude: Double,
        longitude: Double,
        routes: [SubwayRoute]
    ) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.routes = routes
    }

    public func distanceInMeters(latitude otherLatitude: Double, longitude otherLongitude: Double) -> Double {
        let earthRadius = 6_371_000.0
        let latitudeDelta = (otherLatitude - latitude).radians
        let longitudeDelta = (otherLongitude - longitude).radians
        let originLatitude = latitude.radians
        let destinationLatitude = otherLatitude.radians

        let haversine = pow(sin(latitudeDelta / 2), 2)
            + cos(originLatitude) * cos(destinationLatitude) * pow(sin(longitudeDelta / 2), 2)
        return earthRadius * 2 * atan2(sqrt(haversine), sqrt(1 - haversine))
    }
}

public struct NearbyStation: Identifiable, Equatable, Sendable {
    public var id: String { station.id }
    public let station: SubwayStation
    public let distanceInMeters: Double

    public init(station: SubwayStation, distanceInMeters: Double) {
        self.station = station
        self.distanceInMeters = distanceInMeters
    }
}

public extension Collection where Element == SubwayStation {
    func nearest(
        latitude: Double,
        longitude: Double,
        limit: Int = 8
    ) -> [NearbyStation] {
        map { station in
            NearbyStation(
                station: station,
                distanceInMeters: station.distanceInMeters(
                    latitude: latitude,
                    longitude: longitude
                )
            )
        }
        .sorted { $0.distanceInMeters < $1.distanceInMeters }
        .prefix(Swift.max(0, limit))
        .map { $0 }
    }
}

private extension Double {
    var radians: Double { self * .pi / 180 }
}
