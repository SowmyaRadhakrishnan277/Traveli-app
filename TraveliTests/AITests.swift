import XCTest
@testable import Traveli

final class StopVerifierTests: XCTestCase {
    private let centre = GeoPoint(latitude: 38.7223, longitude: -9.1393) // Lisbon

    private func stub(_ name: String, lat: Double = 38.7075, lon: Double = -9.1364,
                      category: PlaceCategory = .landmark) -> PlaceSuggestion {
        .stub(name, lat: lat, lon: lon, category: category)
    }

    func testKeepsRealPlacesAndUsesMapNameAndCoordinates() async {
        let places = QueryStubPlacesService(byKeyword: ["praca": [stub("Praça do Comércio")]])
        let result = await StopVerifier(places: places).verify(
            [StopCandidate(name: "Praca do Comercio", category: "park", timeSlot: "afternoon")],
            destination: "Lisbon", centre: centre
        )
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].name, "Praça do Comércio", "Name comes from the map, not the model")
        XCTAssertEqual(result[0].category, .landmark, "Map category wins over the model's guess")
        XCTAssertEqual(result[0].timeSlot, .afternoon)
    }

    func testDropsHallucinatedAndWrongCityPlaces() async {
        let paris = stub("Louvre", lat: 48.8606, lon: 2.3376)
        let places = QueryStubPlacesService(byKeyword: ["louvre": [paris]])
        let result = await StopVerifier(places: places).verify(
            [StopCandidate(name: "Castle of Imaginary Dreams", category: "landmark", timeSlot: "morning"),
             StopCandidate(name: "Louvre", category: "museum", timeSlot: "afternoon")],
            destination: "Lisbon", centre: centre
        )
        XCTAssertTrue(result.isEmpty, "Unknown place and a match 1,400 km away are both rejected")
    }

    func testSkipsDuplicatesAndPreviouslyUsedPlaces() async {
        let places = QueryStubPlacesService(byKeyword: ["tower": [stub("Belém Tower")]])
        let verifier = StopVerifier(places: places)
        let first = await verifier.verify(
            [StopCandidate(name: "tower", category: "landmark", timeSlot: "morning"),
             StopCandidate(name: "tower", category: "landmark", timeSlot: "afternoon")],
            destination: "Lisbon", centre: centre
        )
        XCTAssertEqual(first.count, 1)
        let again = await verifier.verify(
            [StopCandidate(name: "tower", category: "landmark", timeSlot: "morning")],
            destination: "Lisbon", centre: centre, excluding: [StopVerifier.key("Belém Tower")]
        )
        XCTAssertTrue(again.isEmpty)
    }

    func testUnknownSlotFallsBackToPositionAndResultIsSortedByTime() async {
        let places = QueryStubPlacesService(byKeyword: [
            "aaa": [stub("A")], "bbb": [stub("B", lat: 38.71, lon: -9.14)],
        ])
        let result = await StopVerifier(places: places).verify(
            [StopCandidate(name: "bbb", category: "park", timeSlot: "evening"),
             StopCandidate(name: "aaa", category: "park", timeSlot: "??")],
            destination: "Lisbon", centre: centre
        )
        XCTAssertEqual(result.map(\.name), ["A", "B"]) // "??" falls back to index 1 = afternoon, before evening
    }

    func testSearchFailureSkipsCandidateInsteadOfCrashing() async {
        let result = await StopVerifier(places: StubPlacesService(error: StubError())).verify(
            [StopCandidate(name: "Anything", category: "park", timeSlot: "morning")],
            destination: "Lisbon", centre: centre
        )
        XCTAssertTrue(result.isEmpty)
    }
}

final class FallbackItineraryServiceTests: XCTestCase {
    private let request = ItineraryRequest(destination: "Lisbon",
                                           startDate: TestSupport.date(2026, 3, 1), endDate: TestSupport.date(2026, 3, 1))
    private let sample = MockItineraryService(placesService: nil, latency: .zero, calendar: TestSupport.calendar)

    func testUsesPrimaryWhenItSucceeds() async throws {
        let ai = Itinerary(days: [], origin: .ai)
        let service = FallbackItineraryService(primary: StubItineraryService(result: .success(ai)), fallback: sample)
        let result = try await service.generateItinerary(for: request)
        XCTAssertEqual(result.origin, .ai)
    }

    func testFallsBackToSampleWithReasonWhenAIIsUnavailable() async throws {
        let failing = StubItineraryService(result: .failure(ItineraryError.aiUnavailable(reason: "Turn on Apple Intelligence.")))
        let result = try await FallbackItineraryService(primary: failing, fallback: sample).generateItinerary(for: request)
        XCTAssertEqual(result.origin, .sample)
        XCTAssertFalse(result.days.isEmpty)
        XCTAssertTrue(result.notice.contains("Turn on Apple Intelligence."))
        XCTAssertTrue(result.notice.contains("sample"))
    }

    func testFallsBackOnUnexpectedErrors() async throws {
        let failing = StubItineraryService(result: .failure(StubError()))
        let result = try await FallbackItineraryService(primary: failing, fallback: sample).generateItinerary(for: request)
        XCTAssertEqual(result.origin, .sample)
        XCTAssertFalse(result.notice.isEmpty)
    }

    func testValidationErrorsAreNotSwallowed() async {
        let failing = StubItineraryService(result: .failure(ItineraryError.invalidDateRange))
        do {
            _ = try await FallbackItineraryService(primary: failing, fallback: sample).generateItinerary(for: request)
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? ItineraryError, .invalidDateRange)
        }
    }

    func testWithoutPrimaryUsesSample() async throws {
        let result = try await FallbackItineraryService(primary: nil, fallback: sample).generateItinerary(for: request)
        XCTAssertEqual(result.origin, .sample)
    }
}

@MainActor
final class AIPlannerIntegrationTests: XCTestCase {
    func testPlannerStoresOriginAndNoticeOnTrip() async throws {
        let day = DayProposal(date: TestSupport.date(2026, 3, 1), places: [
            PlaceProposal(name: "A", category: .landmark, location: GeoPoint(latitude: 38.7, longitude: -9.1), timeSlot: .morning),
            PlaceProposal(name: "B", category: .cafe, location: GeoPoint(latitude: 38.71, longitude: -9.12), timeSlot: .afternoon),
        ])
        let planner = TripPlanner(
            itinerary: StubItineraryService(result: .success(Itinerary(days: [day], origin: .ai, notice: "hello"))),
            safety: MockSafetyScoringService(), routing: HeuristicRoutingService()
        )
        let trip = try await planner.buildTrip(destination: "Lisbon", startDate: TestSupport.date(2026, 3, 1),
                                               endDate: TestSupport.date(2026, 3, 1), preferences: "food")
        XCTAssertTrue(trip.isAIGenerated)
        XCTAssertEqual(trip.generationNote, "hello")
        XCTAssertEqual(trip.sortedDays.first?.sortedPlaces.map(\.name), ["A", "B"])
    }
}
