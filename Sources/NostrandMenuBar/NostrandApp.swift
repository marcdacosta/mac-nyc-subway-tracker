import SwiftUI

@main
struct NostrandApp: App {
    @StateObject private var store = ArrivalStore()

    var body: some Scene {
        MenuBarExtra {
            ArrivalsMenuView(store: store)
        } label: {
            Image(nsImage: StatusBarIcon.image(routeID: store.routeFilterID))
                .renderingMode(.original)
                .resizable()
                .interpolation(.high)
                .frame(width: 18, height: 18)
                .accessibilityLabel(statusIconAccessibilityLabel)
                .id(store.routeFilterID ?? "all-trains")
        }
        .menuBarExtraStyle(.window)
    }

    private var statusIconAccessibilityLabel: String {
        store.routeFilterID.map { "\($0) train times" } ?? "All train times"
    }
}
