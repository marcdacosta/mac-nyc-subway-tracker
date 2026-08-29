# NYC Subway

NYC Subway is a native macOS menu-bar app for live subway arrivals, with Nostrand Avenue's Manhattan-bound A train as its default. It uses [Transiter's](https://github.com/jamespfennell/transiter) JSON API and has no third-party runtime dependencies.

## Run it

Requirements: macOS 13 or newer and Xcode Command Line Tools.

```sh
make test
make run
```

`make run` creates an ad-hoc-signed `.build/NYC Subway.app` and opens it. The app has no Dock icon; look for the circular route badge in the menu bar. To keep it permanently, copy the built app to `/Applications` and add it under System Settings → General → Login Items.

Open the station controls with the sliders button in the popover. From there you can:

- use a one-shot location fix to select the nearest subway station;
- choose one of the nearby alternatives;
- search all subway stations manually;
- show all routes or one route; and
- switch between northbound and southbound arrivals.

The app remembers the selected station, route filter, and direction between launches.

## Data flow

For arrivals, the app requests the selected parent station:

```text
https://demo.transiter.dev/systems/us-ny-subway/stops/{stationID}
```

- `A46` is Nostrand Avenue on the A/C line.
- A `directionId` of `false` represents northbound service and `true` represents southbound service in the MTA feed.
- Results can be filtered by route, are ordered by departure time, and refresh every 30 seconds while the popover is open.
- The station catalog is loaded without stop times and used for manual search and local distance calculations.

The public Transiter demo is best-effort. It is convenient for development, but a durable release should point the client at [a Transiter instance you operate](https://docs.transiter.dev/deployment/). Transiter ingests the MTA's static GTFS and ACE GTFS-realtime feeds, persists them in Postgres/PostGIS, and exposes a much simpler JSON API.

## Location and privacy

[Core Location on macOS](https://support.apple.com/guide/mac-help/allow-apps-to-see-the-location-of-your-mac-mh35873/mac) derives the Mac's position from nearby Wi-Fi networks; Macs do not have GPS. That is usually suitable for ranking nearby subway stations in a dense city, but it should not be treated as accurate enough to choose an entrance, platform, or travel direction. Desktop Macs, Ethernet-only use, disabled Wi-Fi, sparse Wi-Fi mapping, and stale observations can all produce coarse or unavailable results.

The implemented location flow:

1. Keeps the saved/manual station active until the user chooses **Use Current Location**.
2. Requests a one-shot Core Location fix and reads `horizontalAccuracy`.
3. Ranks the already-downloaded parent-station catalog locally; coordinates are not sent to Transiter.
4. Selects the nearest station and shows nearby alternatives when the fix is approximate.
5. Keeps manual station, route, and direction controls available after location selection.

Transiter also has a server-side `DISTANCE` stop search, but using it would send the Mac's coordinates to the Transiter operator. NYC Subway intentionally does not call that endpoint.

The app bundle includes the required [`NSLocationWhenInUseUsageDescription`](https://developer.apple.com/documentation/bundleresources/information-property-list/nslocationwheninuseusagedescription) privacy string. macOS may show a location indicator while the one-shot request is active.

## Development

```sh
swift build
swift test
```

`NostrandCore` owns Transiter decoding and filtering. `NostrandMenuBar` owns the SwiftUI menu-bar presentation and refresh state.
