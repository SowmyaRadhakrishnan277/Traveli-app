import SwiftUI

/// Composition root: the one place that decides which service implementations the app uses.
/// To go live, swap `MockItineraryService` / `MockSafetyScoringService` for network-backed ones.
struct AppEnvironment: Sendable {
    var planner: TripPlanner
    var places: PlacesService

    static let live: AppEnvironment = {
        let places = MapKitPlacesService()
        return AppEnvironment(
            planner: TripPlanner(
                itinerary: MockItineraryService(placesService: places),
                safety: MockSafetyScoringService(),
                routing: MapKitRoutingService()
            ),
            places: places
        )
    }()
}

private struct AppEnvironmentKey: EnvironmentKey {
    static let defaultValue = AppEnvironment.live
}

extension EnvironmentValues {
    var appEnvironment: AppEnvironment {
        get { self[AppEnvironmentKey.self] }
        set { self[AppEnvironmentKey.self] = newValue }
    }
}
