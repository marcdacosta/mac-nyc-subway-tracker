import Foundation
@testable import MacNYCSubwayTrackerCore
import XCTest

final class TransiterClientTests: XCTestCase {
    func testDecodesAndFiltersSelectedRouteAndDirection() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let data = Data(
            """
            {
              "stopTimes": [
                {
                  "arrival": { "time": "1700000180" },
                  "departure": { "time": "1700000180" },
                  "trip": {
                    "id": "a-later",
                    "route": { "id": "A" },
                    "destination": { "name": "Inwood-207 St" },
                    "directionId": false
                  }
                },
                {
                  "arrival": { "time": "1700000060" },
                  "trip": {
                    "id": "a-next",
                    "route": { "id": "A" },
                    "destination": { "name": "Inwood-207 St" },
                    "directionId": false
                  }
                },
                {
                  "arrival": { "time": "1700000120" },
                  "trip": {
                    "id": "c-train",
                    "route": { "id": "C" },
                    "destination": { "name": "168 St" },
                    "directionId": false
                  }
                },
                {
                  "arrival": { "time": "1700000090" },
                  "trip": {
                    "id": "southbound-a",
                    "route": { "id": "A" },
                    "destination": { "name": "Far Rockaway-Mott Av" },
                    "directionId": true
                  }
                }
              ]
            }
            """.utf8
        )

        let arrivals = try TransiterClient.decodeArrivals(
            from: data,
            routeID: "A",
            northbound: true,
            now: now
        )

        XCTAssertEqual(arrivals.map(\.destination), ["Inwood-207 St", "Inwood-207 St"])
        XCTAssertEqual(arrivals.map(\.time), [
            Date(timeIntervalSince1970: 1_700_000_060),
            Date(timeIntervalSince1970: 1_700_000_180)
        ])
    }

    func testAcceptsNumericTimestampsAndDropsOldArrivals() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let data = Data(
            """
            {
              "stopTimes": [
                {
                  "departure": { "time": 1699999969 },
                  "trip": {
                    "id": "too-old",
                    "route": { "id": "A" },
                    "destination": { "name": "Inwood-207 St" },
                    "directionId": false
                  }
                },
                {
                  "departure": { "time": 1700000030 },
                  "trip": {
                    "id": "numeric-time",
                    "route": { "id": "A" },
                    "destination": { "name": "Inwood-207 St" },
                    "directionId": false
                  }
                }
              ]
            }
            """.utf8
        )

        let arrivals = try TransiterClient.decodeArrivals(from: data, now: now)

        XCTAssertEqual(arrivals.count, 1)
        XCTAssertEqual(arrivals.first?.time, Date(timeIntervalSince1970: 1_700_000_030))
    }

    func testFiltersAllRoutesAndEitherDirection() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let data = Data(
            """
            {
              "stopTimes": [
                {
                  "departure": { "time": "1700000060" },
                  "trip": {
                    "id": "northbound-a",
                    "route": { "id": "A", "color": "0062CF" },
                    "destination": { "name": "Inwood-207 St" },
                    "directionId": false
                  }
                },
                {
                  "departure": { "time": "1700000120" },
                  "trip": {
                    "id": "northbound-c",
                    "route": { "id": "C", "color": "0062CF" },
                    "destination": { "name": "168 St" },
                    "directionId": false
                  }
                },
                {
                  "departure": { "time": "1700000090" },
                  "trip": {
                    "id": "southbound-a",
                    "route": { "id": "A", "color": "0062CF" },
                    "destination": { "name": "Far Rockaway-Mott Av" },
                    "directionId": true
                  }
                }
              ]
            }
            """.utf8
        )

        let northbound = try TransiterClient.decodeArrivals(
            from: data,
            routeID: nil,
            northbound: true,
            now: now
        )
        let southbound = try TransiterClient.decodeArrivals(
            from: data,
            routeID: nil,
            northbound: false,
            now: now
        )

        XCTAssertEqual(northbound.map(\.routeID), ["A", "C"])
        XCTAssertEqual(northbound.map(\.routeColor), ["0062CF", "0062CF"])
        XCTAssertEqual(southbound.map(\.routeID), ["A"])
        XCTAssertEqual(southbound.map(\.destination), ["Far Rockaway-Mott Av"])
    }

    func testRanksNearbyStationsLocally() {
        let stations = [
            SubwayStation(
                id: "west",
                name: "West Station",
                latitude: 40.68138,
                longitude: -73.956848,
                routes: []
            ),
            SubwayStation(
                id: "center",
                name: "Center Station",
                latitude: 40.680438,
                longitude: -73.950426,
                routes: []
            ),
            SubwayStation(
                id: "east",
                name: "East Station",
                latitude: 40.679921,
                longitude: -73.940858,
                routes: []
            )
        ]

        let nearest = stations.nearest(
            latitude: 40.680438,
            longitude: -73.950426,
            limit: 2
        )

        XCTAssertEqual(nearest.map(\.station.id), ["center", "west"])
        XCTAssertEqual(nearest.first?.distanceInMeters ?? -1, 0, accuracy: 0.01)
        XCTAssertEqual(nearest.count, 2)
    }
}
