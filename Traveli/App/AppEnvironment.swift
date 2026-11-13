import SwiftUI

/// Composition root: the one place that decides which service implementations the app uses.
/// Itineraries use on-device AI when available (falling back to a sample); safety scores are still mock.
struct AppEnvironment: Sendable {
    var planner: TripPlanner
    var places: PlacesService

    static func makeItineraryService(places: PlacesService) -> ItineraryService {
        let sample = MockItineraryService(placesService: places)
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return FallbackItineraryService(primary: AIItineraryService(places: places), fallback: sample)
        }
        #endif
        return FallbackItineraryService(primary: nil, fallback: sample)
    }

    static let live: AppEnvironment = {
        let places = MapKitPlacesService()
        return AppEnvironment(
            planner: TripPlanner(
                itinerary: makeItineraryService(places: places),
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
