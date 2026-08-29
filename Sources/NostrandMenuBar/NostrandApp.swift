import SwiftUI

@main
struct NostrandApp: App {
    @StateObject private var store = ArrivalStore()

    var body: some Scene {
        MenuBarExtra {
            ArrivalsMenuView(store: store)
        } label: {
            TrainBadge(size: 18, style: .menuBar)
        }
        .menuBarExtraStyle(.window)
    }
}
