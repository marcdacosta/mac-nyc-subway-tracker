import AppKit
import NostrandCore
import SwiftUI

struct ArrivalsMenuView: View {
    @ObservedObject var store: ArrivalStore
    @StateObject private var locationProvider = LocationProvider()
    @State private var isShowingStationSwitcher = false

    private let refreshTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if isShowingStationSwitcher {
                StationSwitcherView(
                    store: store,
                    locationProvider: locationProvider,
                    isPresented: $isShowingStationSwitcher
                )
            } else {
                arrivalsContent
                Divider()
                footer
            }
        }
        .frame(width: 350)
        .task {
            await store.start()
        }
        .onReceive(refreshTimer) { _ in
            guard !isShowingStationSwitcher else { return }
            store.refresh()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            TrainBadge(
                size: 34,
                routeID: headerRoute.id,
                colorHex: headerRoute.color
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(store.selectedStation.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(selectionSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if store.isLoading && !isShowingStationSwitcher {
                ProgressView()
                    .controlSize(.small)
            }

            Button {
                withAnimation(.easeOut(duration: 0.16)) {
                    isShowingStationSwitcher.toggle()
                }
            } label: {
                Image(systemName: isShowingStationSwitcher ? "xmark" : "slider.horizontal.3")
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.borderless)
            .help(isShowingStationSwitcher ? "Close station settings" : "Change station")
            .accessibilityLabel(isShowingStationSwitcher ? "Close station settings" : "Change station")
        }
        .padding(14)
    }

    private var headerRoute: SubwayRoute {
        if let routeID = store.routeFilterID,
           let route = store.selectedStation.routes.first(where: { $0.id == routeID }) {
            return route
        }
        return store.selectedStation.routes.first ?? SubwayRoute(id: "A", color: "0062CF")
    }

    private var selectionSummary: String {
        if store.selectedStation.id == "A46",
           store.routeFilterID == "A",
           store.direction == .northbound {
            return "Manhattan-bound · A train"
        }

        let trains = store.routeFilterID.map { "\($0) train" } ?? "All trains"
        return "\(store.direction.title) · \(trains)"
    }

    @ViewBuilder
    private var arrivalsContent: some View {
        if store.isLoading && store.arrivals.isEmpty {
            EmptyStateView(
                title: "Loading live times",
                systemImage: "clock.arrow.circlepath",
                message: "Checking the latest subway feed."
            )
            .frame(minHeight: 180)
        } else if let errorMessage = store.errorMessage, store.arrivals.isEmpty {
            EmptyStateView(
                title: "Times unavailable",
                systemImage: "wifi.exclamationmark",
                message: errorMessage,
                actionTitle: "Try Again"
            ) {
                store.refresh()
            }
            .frame(minHeight: 180)
            .padding(.horizontal, 12)
        } else if !store.isLoading && store.arrivals.isEmpty {
            EmptyStateView(
                title: "No upcoming trains",
                systemImage: "tram",
                message: "The live feed has no matching arrivals right now."
            )
            .frame(minHeight: 180)
            .padding(.horizontal, 12)
        } else {
            VStack(spacing: 0) {
                if let errorMessage = store.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                    Divider()
                }

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(spacing: 0) {
                        ForEach(Array(store.arrivals.prefix(6).enumerated()), id: \.element.id) { index, arrival in
                            ArrivalRow(arrival: arrival, now: context.date)
                            if index < min(store.arrivals.count, 6) - 1 {
                                Divider()
                                    .padding(.leading, 58)
                            }
                        }
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button {
                store.refresh()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(store.isLoading)

            Spacer()

            if let updated = store.lastUpdated {
                Text("Updated \(updated, style: .relative)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

private struct StationSwitcherView: View {
    @ObservedObject var store: ArrivalStore
    @ObservedObject var locationProvider: LocationProvider
    @Binding var isPresented: Bool
    @State private var searchText = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                locationSection
                Divider()
                searchSection
                Divider()
                filtersSection

                HStack {
                    Spacer()
                    Button("Done") {
                        isPresented = false
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(14)
        }
        .frame(height: 440)
    }

    private var locationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Nearby stations")
                .font(.headline)

            Button {
                useCurrentLocation()
            } label: {
                HStack {
                    Label("Use Current Location", systemImage: "location.fill")
                    Spacer()
                    if locationProvider.isLocating || store.isLoadingStations {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }
            .disabled(locationProvider.isLocating || store.isLoadingStations)

            Text("Your coordinates stay on this Mac and are used only to rank stations.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if let message = store.locationMessage {
                Label(message, systemImage: "location.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !store.nearbyStations.isEmpty {
                VStack(spacing: 2) {
                    ForEach(store.nearbyStations.prefix(5)) { nearby in
                        stationButton(
                            nearby.station,
                            detail: distanceLabel(nearby.distanceInMeters)
                        )
                    }
                }
            }
        }
    }

    private var searchSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Choose a station")
                .font(.headline)

            TextField("Search subway stations", text: $searchText)
                .textFieldStyle(.roundedBorder)

            if store.isLoadingStations {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading stations…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            } else if let stationLoadError = store.stationLoadError {
                VStack(alignment: .leading, spacing: 6) {
                    Text(stationLoadError)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Try Again") {
                        Task {
                            await store.loadStations()
                        }
                    }
                }
            } else if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Type a station name to search the full subway system.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else if filteredStations.isEmpty {
                Text("No matching stations")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 2) {
                    ForEach(filteredStations.prefix(8)) { station in
                        stationButton(station)
                    }
                }
            }
        }
    }

    private var filtersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Trains at \(store.selectedStation.name)")
                .font(.headline)

            Picker(
                "Route",
                selection: Binding(
                    get: { store.routeFilterID ?? "*" },
                    set: { store.selectRoute($0 == "*" ? nil : $0) }
                )
            ) {
                Text("All trains").tag("*")
                ForEach(store.selectedStation.routes) { route in
                    Text("\(route.id) train").tag(route.id)
                }
            }
            .pickerStyle(.menu)

            Picker(
                "Direction",
                selection: Binding(
                    get: { store.direction },
                    set: { store.selectDirection($0) }
                )
            ) {
                ForEach(TravelDirection.allCases) { direction in
                    Text(direction.title).tag(direction)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private var filteredStations: [SubwayStation] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }

        return store.stations.filter { station in
            station.name.localizedCaseInsensitiveContains(query)
                || station.routes.contains { $0.id.localizedCaseInsensitiveContains(query) }
        }
    }

    private func stationButton(_ station: SubwayStation, detail: String? = nil) -> some View {
        Button {
            store.selectStation(station)
        } label: {
            HStack(spacing: 8) {
                HStack(spacing: 3) {
                    ForEach(station.routes.prefix(3)) { route in
                        TrainBadge(
                            size: 18,
                            routeID: route.id,
                            colorHex: route.color
                        )
                    }
                }
                .frame(minWidth: 18, alignment: .leading)

                Text(station.name)
                    .lineLimit(1)
                Spacer()
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if station.id == store.selectedStation.id {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private func useCurrentLocation() {
        Task {
            await store.loadStations()
            guard !store.stations.isEmpty else {
                store.setLocationError("Load the station list before using your location.")
                return
            }

            locationProvider.requestLocation { result in
                switch result {
                case let .success(location):
                    store.applyLocation(
                        latitude: location.coordinate.latitude,
                        longitude: location.coordinate.longitude,
                        horizontalAccuracy: location.horizontalAccuracy
                    )
                case let .failure(error):
                    store.setLocationError(error.localizedDescription)
                }
            }
        }
    }

    private func distanceLabel(_ meters: Double) -> String {
        let feet = meters * 3.28084
        if feet < 1_000 {
            return "\(Int(feet.rounded())) ft"
        }
        return String(format: "%.1f mi", meters / 1_609.344)
    }
}

private struct EmptyStateView: View {
    let title: String
    let systemImage: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    init(
        title: String,
        systemImage: String,
        message: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.systemImage = systemImage
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.title)
                .foregroundStyle(.secondary)

            Text(title)
                .font(.headline)

            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let actionTitle, let action {
                Button(actionTitle) {
                    action()
                }
                .padding(.top, 4)
            }
        }
    }
}

private struct ArrivalRow: View {
    let arrival: Arrival
    let now: Date

    var body: some View {
        HStack(spacing: 10) {
            TrainBadge(
                size: 28,
                routeID: arrival.routeID,
                colorHex: arrival.routeColor
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(arrival.destination)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(arrival.time, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(countdown)
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(secondsUntilArrival < 60 ? .orange : .primary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var secondsUntilArrival: TimeInterval {
        arrival.time.timeIntervalSince(now)
    }

    private var countdown: String {
        if secondsUntilArrival <= 30 {
            return "Due"
        }

        let minutes = max(1, Int(ceil(secondsUntilArrival / 60)))
        return "\(minutes) min"
    }
}
