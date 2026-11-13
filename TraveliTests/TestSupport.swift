import Foundation
import SwiftData
import XCTest
@testable import Traveli

enum TestSupport {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    static func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d))!
    }

    /// SwiftData destroys models when their container is deallocated, so keep
    /// every test container alive for the whole test run.
    @MainActor private static var retainedContainers: [ModelContainer] = []

    @MainActor
    static func makeContainer() throws -> ModelContainer {
        let container = try ModelContainer(
            for: Trip.self, Day.self, Place.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        retainedContainers.append(container)
        return container
    }

    static let planner = TripPlanner(
        itinerary: MockItineraryService(placesService: nil, latency: .zero, calendar: calendar),
        safety: MockSafetyScoringService(),
        routing: HeuristicRoutingService()
    )
}

struct StubPlacesService: PlacesService {
    var results: [PlaceSuggestion] = []
    var error: Error?

    func search(query: String, near: GeoPoint?) async throws -> [PlaceSuggestion] {
        if let error { throw error }
        return results
    }
}

struct StubError: Error {}

extension PlaceSuggestion {
    static func stub(_ name: String, lat: Double = 38.71, lon: Double = -9.14,
                     category: PlaceCategory = .cafe) -> PlaceSuggestion {
        PlaceSuggestion(name: name, subtitle: "Test St", category: category,
                        location: GeoPoint(latitude: lat, longitude: lon))
    }
}

/// Answers searches by matching a substring of the query, like a tiny fake map.
struct QueryStubPlacesService: PlacesService {
    var byKeyword: [String: [PlaceSuggestion]]

    func search(query: String, near: GeoPoint?) async throws -> [PlaceSuggestion] {
        for (keyword, results) in byKeyword where query.localizedCaseInsensitiveContains(keyword) {
            return results
        }
        return []
    }
}

struct StubItineraryService: ItineraryService {
    var result: Result<Itinerary, Error>

    func generateItinerary(for request: ItineraryRequest) async throws -> Itinerary {
        try result.get()
    }
}
