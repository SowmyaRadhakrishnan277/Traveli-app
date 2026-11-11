import SwiftData
import SwiftUI

@main
struct WayfarerApp: App {
    @State private var network = NetworkMonitor()

    var body: some Scene {
        WindowGroup {
            TripListView()
                .environment(network)
        }
        // Local-only storage: saved trips are readable offline and never leave the device.
        .modelContainer(for: [Trip.self, Day.self, Place.self])
    }
}
