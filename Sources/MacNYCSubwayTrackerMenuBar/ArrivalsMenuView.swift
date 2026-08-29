import AppKit
import MacNYCSubwayTrackerCore
import SwiftUI

struct ArrivalsMenuView: View {
    @ObservedObject var store: ArrivalStore
    @ObservedObject var locationProvider: LocationProvider
    @State private var isShowingStationSwitcher = false

    private let refreshTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            if store.needsSetup {
                StationSetupView(
                    store: store,
                    onUseAutomaticLocation: enableAutomaticLocation
                )
            } else if store.selectedStation == nil {
                AutomaticStationView(
                    store: store,
                    locationProvider: locationProvider,
                    onRetry: enableAutomaticLocation
                )
            } else {
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
        }
        .frame(width: 350)
        .onAppear {
            if !store.needsSetup, store.selectedStation != nil {
                store.refresh()
            }

            if store.stationSelectionMode == .automatic,
               !locationProvider.isMonitoring {
                enableAutomaticLocation()
            }
        }
        .onReceive(refreshTimer) { _ in
            guard !store.needsSetup,
                  store.selectedStation != nil,
                  !isShowingStationSwitcher
            else {
                return
            }
            store.refresh()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            if let headerRoute {
                TrainBadge(
                    size: 34,
                    routeID: headerRoute.id,
                    colorHex: headerRoute.color
                )
            } else {
                Image(systemName: "tram.fill")
                    .font(.title2)
                    .frame(width: 34, height: 34)
                    .background(.quaternary, in: Circle())
                    .accessibilityLabel("All trains")
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(store.selectedStation?.name ?? "Mac NYC Subway Tracker")
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

    private var headerRoute: SubwayRoute? {
        guard let station = store.selectedStation else { return nil }
        if let routeFilterID = store.routeFilterID,
           let route = station.routes.first(where: { $0.id == routeFilterID }) {
            return route
        }
        return station.routes.first
    }

    private var selectionSummary: String {
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

    private func enableAutomaticLocation() {
        store.enableAutomaticStationSelection()

        Task {
            await store.loadStations()
            guard !store.stations.isEmpty else {
                store.setLocationError(
                    store.stationLoadError ?? "Load the station list before using automatic location."
                )
                return
            }

            locationProvider.startMonitoring { location in
                store.applyLocation(
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude,
                    horizontalAccuracy: location.horizontalAccuracy
                )
            } onError: { error in
                store.setLocationError(error.localizedDescription)
            }
        }
    }
}

private struct StationSetupView: View {
    @ObservedObject var store: ArrivalStore
    let onUseAutomaticLocation: () -> Void

    @State private var isChoosingHome = false
    @State private var searchText = ""

    var body: some View {
        Group {
            if isChoosingHome {
                homeStationChooser
            } else {
                setupChoices
            }
        }
        .frame(minHeight: 390)
        .padding(22)
    }

    private var setupChoices: some View {
        VStack(spacing: 16) {
            Image(systemName: "tram.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text("Choose where to start")
                    .font(.title2.weight(.semibold))
                Text("Follow this Mac to the nearest station, or keep one home station selected.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                onUseAutomaticLocation()
            } label: {
                Label("Use Nearest Station", systemImage: "location.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Text("Keeps updating while the tracker is running. Your coordinates stay on this Mac.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                withAnimation(.easeOut(duration: 0.18)) {
                    isChoosingHome = true
                }
            } label: {
                Label("Choose a Home Station", systemImage: "house.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    private var homeStationChooser: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Button {
                    withAnimation(.easeOut(duration: 0.18)) {
                        isChoosingHome = false
                    }
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.borderless)
                .help("Back")

                Text("Choose a home station")
                    .font(.headline)
            }

            TextField("Search stations or routes", text: $searchText)
                .textFieldStyle(.roundedBorder)

            if store.isLoadingStations {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading subway stations…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 240)
            } else if let stationLoadError = store.stationLoadError {
                EmptyStateView(
                    title: "Stations unavailable",
                    systemImage: "wifi.exclamationmark",
                    message: stationLoadError,
                    actionTitle: "Try Again"
                ) {
                    Task { await store.loadStations() }
                }
                .frame(maxWidth: .infinity, minHeight: 240)
            } else if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                EmptyStateView(
                    title: "Find your station",
                    systemImage: "magnifyingglass",
                    message: "Search by station name or train, then choose the station to keep selected."
                )
                .frame(maxWidth: .infinity, minHeight: 240)
            } else if filteredStations.isEmpty {
                EmptyStateView(
                    title: "No matching stations",
                    systemImage: "questionmark.circle",
                    message: "Try another station name or route."
                )
                .frame(maxWidth: .infinity, minHeight: 240)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(filteredStations.prefix(10)) { station in
                            stationButton(station)
                        }
                    }
                }
                .frame(height: 240)
            }
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

    private func stationButton(_ station: SubwayStation) -> some View {
        Button {
            store.selectHomeStation(station)
        } label: {
            HStack(spacing: 8) {
                RouteBadgeGroup(routes: station.routes)
                Text(station.name)
                    .lineLimit(1)
                Spacer()
            }
            .contentShape(Rectangle())
            .padding(.vertical, 5)
        }
        .buttonStyle(.plain)
    }
}

private struct AutomaticStationView: View {
    @ObservedObject var store: ArrivalStore
    @ObservedObject var locationProvider: LocationProvider
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            if locationProvider.isLocating {
                ProgressView()
                    .controlSize(.large)
            } else {
                Image(systemName: "location.circle")
                    .font(.system(size: 42))
                    .foregroundStyle(.secondary)
            }

            Text("Finding nearby trains")
                .font(.title3.weight(.semibold))

            Text(store.locationMessage ?? "Waiting for this Mac's current location.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button("Try Location Again", action: onRetry)
                .buttonStyle(.borderedProminent)

            Button("Choose a Home Station") {
                store.clearStationSelection()
            }
            .buttonStyle(.borderless)

            Button("Open Location Settings") {
                openLocationSettings()
            }
            .buttonStyle(.borderless)
        }
        .frame(minHeight: 320)
        .padding(24)
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
                stationModeSection
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

    private var stationModeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Station mode")
                .font(.headline)

            Toggle(
                "Follow this Mac",
                isOn: Binding(
                    get: { store.stationSelectionMode == .automatic },
                    set: { followsMac in
                        if followsMac {
                            enableAutomaticLocation()
                        } else {
                            locationProvider.stopMonitoring()
                            store.keepCurrentStationAsHome()
                        }
                    }
                )
            )

            Text(
                store.stationSelectionMode == .automatic
                    ? "The nearest station updates as macOS reports that this Mac has moved. Coordinates stay on this Mac."
                    : "This station stays selected until you choose another one."
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            if store.stationSelectionMode == .automatic {
                HStack(spacing: 7) {
                    if locationProvider.isLocating {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: locationProvider.isMonitoring ? "location.fill" : "location.slash")
                            .foregroundStyle(locationProvider.isMonitoring ? Color.accentColor : .secondary)
                    }

                    Text(store.locationMessage ?? "Automatic location is on.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !locationProvider.isMonitoring {
                    HStack(spacing: 10) {
                        Button("Try Again") {
                            enableAutomaticLocation()
                        }
                        Button("Location Settings") {
                            openLocationSettings()
                        }
                    }
                    .buttonStyle(.borderless)
                }
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
            Text("Choose a home station")
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
                        Task { await store.loadStations() }
                    }
                }
            } else if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Choosing a station here turns off automatic location.")
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

    @ViewBuilder
    private var filtersSection: some View {
        if let station = store.selectedStation {
            VStack(alignment: .leading, spacing: 10) {
                Text("Trains at \(station.name)")
                    .font(.headline)

                Picker(
                    "Route",
                    selection: Binding(
                        get: { store.routeFilterID ?? "*" },
                        set: { store.selectRoute($0 == "*" ? nil : $0) }
                    )
                ) {
                    Text("All trains").tag("*")
                    ForEach(station.routes) { route in
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
            locationProvider.stopMonitoring()
            store.selectHomeStation(station)
        } label: {
            HStack(spacing: 8) {
                RouteBadgeGroup(routes: station.routes)

                Text(station.name)
                    .lineLimit(1)
                Spacer()
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if station.id == store.selectedStation?.id,
                   store.stationSelectionMode == .home {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private func enableAutomaticLocation() {
        store.enableAutomaticStationSelection()

        Task {
            await store.loadStations()
            guard !store.stations.isEmpty else {
                store.setLocationError(
                    store.stationLoadError ?? "Load the station list before using automatic location."
                )
                return
            }

            locationProvider.startMonitoring { location in
                store.applyLocation(
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude,
                    horizontalAccuracy: location.horizontalAccuracy
                )
            } onError: { error in
                store.setLocationError(error.localizedDescription)
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

private struct RouteBadgeGroup: View {
    let routes: [SubwayRoute]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(routes.prefix(3)) { route in
                TrainBadge(
                    size: 18,
                    routeID: route.id,
                    colorHex: route.color
                )
            }
        }
        .frame(minWidth: 18, alignment: .leading)
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

private func openLocationSettings() {
    guard let url = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices"
    ) else {
        return
    }
    NSWorkspace.shared.open(url)
}
