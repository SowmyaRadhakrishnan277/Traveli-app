import XCTest
@testable import Wayfarer

final class MockItineraryServiceTests: XCTestCase {
    private let service = MockItineraryService(placesService: nil, latency: .zero, calendar: TestSupport.calendar)

    private func request(_ destination: String, days: Int) -> ItineraryRequest {
        ItineraryRequest(destination: destination,
                         startDate: TestSupport.date(2026, 3, 1),
                         endDate: TestSupport.date(2026, 3, days))
    }

    func testOneDayPerDateWithThreeOrderedSlots() async throws {
        let days = try await service.generateItinerary(for: request("Lisbon", days: 3))
        XCTAssertEqual(days.count, 3)
        for day in days {
            XCTAssertEqual(day.places.map(\.timeSlot), [.morning, .afternoon, .evening])
        }
    }

    func testIsDeterministic() async throws {
        let first = try await service.generateItinerary(for: request("Paris", days: 4))
        let second = try await service.generateItinerary(for: request("Paris", days: 4))
        XCTAssertEqual(first, second)
    }

    func testDestinationMatchingIgnoresCaseAccentsAndCountrySuffix() async throws {
        let days = try await service.generateItinerary(for: request("  tokyo, Japan ", days: 1))
        XCTAssertEqual(days.count, 1)
        XCTAssertNotNil(MockCityCatalog.template(for: "TÓKYO"))
    }

    func testValidation() async {
        await assertThrows(ItineraryError.emptyDestination) { _ = try await service.generateItinerary(for: request("  ", days: 2)) }
        await assertThrows(ItineraryError.invalidDateRange) {
            let bad = ItineraryRequest(destination: "Lisbon", startDate: TestSupport.date(2026, 3, 5), endDate: TestSupport.date(2026, 3, 1))
            _ = try await service.generateItinerary(for: bad)
        }
        await assertThrows(ItineraryError.tooLong(maxDays: 14)) { _ = try await service.generateItinerary(for: request("Lisbon", days: 15)) }
    }

    func testUnknownDestinationWithoutPlacesServiceFails() async {
        await assertThrows(ItineraryError.destinationNotFound) { _ = try await service.generateItinerary(for: request("Atlantis", days: 1)) }
    }

    func testUnknownDestinationUsesPlacesServiceForCentre() async throws {
        let places = StubPlacesService(results: [.stub("Bruges", lat: 51.2093, lon: 3.2247)])
        let service = MockItineraryService(placesService: places, latency: .zero, calendar: TestSupport.calendar)
        let days = try await service.generateItinerary(for: request("Bruges", days: 2))
        XCTAssertEqual(days.count, 2)
        let centre = GeoPoint(latitude: 51.2093, longitude: 3.2247)
        XCTAssertTrue(days[0].places.allSatisfy { $0.location.distance(to: centre) < 3_000 })
    }

    func testLookupFailureIsReportedFriendly() async {
        let places = StubPlacesService(error: StubError())
        let service = MockItineraryService(placesService: places, latency: .zero, calendar: TestSupport.calendar)
        await assertThrows(ItineraryError.destinationLookupFailed) { _ = try await service.generateItinerary(for: request("Bruges", days: 1)) }
    }

    private func assertThrows(_ expected: ItineraryError, _ body: () async throws -> Void,
                              file: StaticString = #filePath, line: UInt = #line) async {
        do {
            try await body()
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? ItineraryError, expected, file: file, line: line)
        }
    }
}

final class MockSafetyScoringServiceTests: XCTestCase {
    private let service = MockSafetyScoringService()

    private func query(_ category: PlaceCategory, _ slot: TimeSlot) -> SafetyQuery {
        SafetyQuery(name: "X", category: category, location: GeoPoint(latitude: 0, longitude: 0), timeSlot: slot)
    }

    func testNightScoresLowerThanDayForEveryKnownCategory() async {
        for category in PlaceCategory.allCases where category != .other && category != .nightlife {
            let day = await service.assess(query(category, .morning))
            let night = await service.assess(query(category, .evening))
            XCTAssertLessThan(night.score!, day.score!, "\(category)")
        }
    }

    func testKnownCategoryIsFullyPopulated() async {
        let result = await service.assess(query(.landmark, .morning))
        XCTAssertEqual(result.band, .comfortable)
        XCTAssertFalse(result.reason.isEmpty)
        XCTAssertFalse(result.dayNote.isEmpty)
        XCTAssertFalse(result.nightNote.isEmpty)
        XCTAssertFalse(result.sources.isEmpty)
    }

    func testUnknownCategoryHasLimitedDataAndNoScore() async {
        let result = await service.assess(query(.other, .afternoon))
        XCTAssertNil(result.score)
        XCTAssertEqual(result.band, .limitedData)
        XCTAssertEqual(result.confidence, .low)
    }

    func testParkAtNightIsTakeCare() async {
        let result = await service.assess(query(.park, .evening))
        XCTAssertEqual(result.band, .takeCare)
    }
}

final class HeuristicRoutingServiceTests: XCTestCase {
    private let service = HeuristicRoutingService()
    private let origin = GeoPoint(latitude: 38.7075, longitude: -9.1364)

    func testShortHopIsWalking() async {
        let near = GeoPoint(latitude: 38.7075 + 0.003, longitude: -9.1364) // ~330 m
        let estimate = await service.estimate(from: origin, to: near)
        XCTAssertEqual(estimate.mode, .walk)
        XCTAssertTrue((3...8).contains(estimate.minutes), "\(estimate.minutes)")
    }

    func testMediumHopIsTransitAndLongHopIsTaxi() async {
        let mid = await service.estimate(from: origin, to: GeoPoint(latitude: 38.7075 + 0.03, longitude: -9.1364))
        XCTAssertEqual(mid.mode, .transit)
        let far = await service.estimate(from: origin, to: GeoPoint(latitude: 38.7075 + 0.2, longitude: -9.1364))
        XCTAssertEqual(far.mode, .taxi)
        XCTAssertGreaterThan(far.minutes, mid.minutes)
    }

    func testSamePointIsAtLeastOneMinute() async {
        let estimate = await service.estimate(from: origin, to: origin)
        XCTAssertEqual(estimate.minutes, 1)
    }
}
