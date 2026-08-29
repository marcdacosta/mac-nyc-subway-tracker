import Foundation

public struct TransiterClient: Sendable {
    public static let demoBaseURL = URL(string: "https://demo.transiter.dev")!
    public static let systemID = "us-ny-subway"

    private let session: URLSession
    private let baseURL: URL

    public init(
        session: URLSession = .shared,
        baseURL: URL = TransiterClient.demoBaseURL
    ) {
        self.session = session
        self.baseURL = baseURL
    }

    public func fetchArrivals(
        stationID: String,
        routeID: String?,
        northbound: Bool,
        now arrivalsNow: Date = .now
    ) async throws -> [Arrival] {
        let endpoint = baseURL
            .appending(path: "systems")
            .appending(path: Self.systemID)
            .appending(path: "stops")
            .appending(path: stationID)

        let data = try await requestData(from: endpoint)
        return try Self.decodeArrivals(
            from: data,
            routeID: routeID,
            northbound: northbound,
            now: arrivalsNow
        )
    }

    public func fetchStations() async throws -> [SubwayStation] {
        var stations: [SubwayStation] = []
        var firstID: String?
        var seenPageIDs: Set<String> = []

        repeat {
            var components = URLComponents(
                url: baseURL
                    .appending(path: "systems")
                    .appending(path: Self.systemID)
                    .appending(path: "stops"),
                resolvingAgainstBaseURL: false
            )
            var queryItems = [
                URLQueryItem(name: "limit", value: "100"),
                URLQueryItem(name: "filter_by_type", value: "true"),
                URLQueryItem(name: "type", value: "STATION"),
                URLQueryItem(name: "skip_stop_times", value: "true"),
                URLQueryItem(name: "skip_alerts", value: "true"),
                URLQueryItem(name: "skip_transfers", value: "true")
            ]
            if let firstID {
                queryItems.append(URLQueryItem(name: "first_id", value: firstID))
            }
            components?.queryItems = queryItems

            guard let endpoint = components?.url else {
                throw TransiterError.invalidResponse
            }

            let pageData = try await requestData(from: endpoint)
            let page = try JSONDecoder().decode(StopListResponse.self, from: pageData)
            stations.append(contentsOf: page.stops.compactMap(\.subwayStation))

            guard let nextID = page.nextID, seenPageIDs.insert(nextID).inserted else {
                firstID = nil
                continue
            }
            firstID = nextID
        } while firstID != nil

        return Dictionary(grouping: stations, by: \.id)
            .compactMap { $0.value.first }
            .sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
    }

    private func requestData(from endpoint: URL) async throws -> Data {
        var request = URLRequest(url: endpoint)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TransiterError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw TransiterError.httpStatus(httpResponse.statusCode)
        }

        return data
    }

    public static func decodeArrivals(
        from data: Data,
        routeID: String? = nil,
        northbound: Bool = true,
        now: Date
    ) throws -> [Arrival] {
        let stop = try JSONDecoder().decode(StopResponse.self, from: data)
        let recentCutoff = now.addingTimeInterval(-30)

        return stop.stopTimes.compactMap { stopTime in
            guard (routeID == nil || stopTime.trip.route.id == routeID),
                  stopTime.trip.directionID == !northbound,
                  let timestamp = stopTime.departure?.unixTime ?? stopTime.arrival?.unixTime,
                  let destination = stopTime.trip.destination?.name,
                  timestamp >= recentCutoff
            else {
                return nil
            }

            return Arrival(
                id: stopTime.trip.id + "-" + String(Int(timestamp.timeIntervalSince1970)),
                routeID: stopTime.trip.route.id,
                routeColor: stopTime.trip.route.color,
                destination: destination,
                time: timestamp
            )
        }
        .sorted { $0.time < $1.time }
    }
}

public enum TransiterError: LocalizedError, Equatable, Sendable {
    case invalidResponse
    case httpStatus(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "The train service returned an invalid response."
        case let .httpStatus(status):
            "The train service returned HTTP \(status)."
        }
    }
}

private struct StopResponse: Decodable {
    let stopTimes: [StopTime]
}

private struct StopTime: Decodable {
    let arrival: TransitEvent?
    let departure: TransitEvent?
    let trip: Trip
}

private struct TransitEvent: Decodable {
    let unixTime: Date?

    private enum CodingKeys: String, CodingKey {
        case time
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)

        if let value = try? values.decode(String.self, forKey: .time),
           let seconds = TimeInterval(value) {
            unixTime = Date(timeIntervalSince1970: seconds)
        } else if let value = try? values.decode(Int64.self, forKey: .time) {
            unixTime = Date(timeIntervalSince1970: TimeInterval(value))
        } else if let value = try? values.decode(Double.self, forKey: .time) {
            unixTime = Date(timeIntervalSince1970: value)
        } else {
            unixTime = nil
        }
    }
}

private struct Trip: Decodable {
    let id: String
    let route: Route
    let destination: Destination?
    let directionID: Bool?

    private enum CodingKeys: String, CodingKey {
        case id
        case route
        case destination
        case directionID = "directionId"
    }
}

private struct Route: Decodable {
    let id: String
    let color: String?
}

private struct Destination: Decodable {
    let name: String
}

private struct StopListResponse: Decodable {
    let stops: [StationResponse]
    let nextID: String?

    private enum CodingKeys: String, CodingKey {
        case stops
        case nextID = "nextId"
    }
}

private struct StationResponse: Decodable {
    let id: String
    let name: String?
    let type: String?
    let latitude: Double?
    let longitude: Double?
    let serviceMaps: [ServiceMap]?

    var subwayStation: SubwayStation? {
        guard type == "STATION",
              let name,
              let latitude,
              let longitude
        else {
            return nil
        }

        let preferredServiceMap = serviceMaps?.first { $0.configID == "alltimes" }
            ?? serviceMaps?.first { $0.configID == "realtime" }
            ?? serviceMaps?.first
        let routes = Dictionary(grouping: preferredServiceMap?.routes ?? [], by: \.id)
            .compactMap { $0.value.first }
            .map { SubwayRoute(id: $0.id, color: $0.color) }
            .sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }

        return SubwayStation(
            id: id,
            name: name,
            latitude: latitude,
            longitude: longitude,
            routes: routes
        )
    }
}

private struct ServiceMap: Decodable {
    let configID: String
    let routes: [Route]

    private enum CodingKeys: String, CodingKey {
        case configID = "configId"
        case routes
    }
}
