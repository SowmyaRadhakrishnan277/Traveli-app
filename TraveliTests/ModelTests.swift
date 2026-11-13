import SwiftData
import XCTest
@testable import Traveli

@MainActor
final class ModelTests: XCTestCase {
    func testSortedPlacesFollowOrderNotInsertionOrder() throws {
        let day = Day(date: .now)
        day.places = [
            Place(name: "C", category: .cafe, latitude: 0, longitude: 0, timeSlot: .evening, order: 2),
            Place(name: "A", category: .cafe, latitude: 0, longitude: 0, timeSlot: .morning, order: 0),
            Place(name: "B", category: .cafe, latitude: 0, longitude: 0, timeSlot: .afternoon, order: 1),
        ]
        XCTAssertEqual(day.sortedPlaces.map(\.name), ["A", "B", "C"])
    }

    func testApplyOrderRewritesSequentially() {
        let day = Day(date: .now)
        let a = Place(name: "A", category: .park, latitude: 0, longitude: 0, timeSlot: .morning, order: 5)
        let b = Place(name: "B", category: .park, latitude: 0, longitude: 0, timeSlot: .morning, order: 9)
        day.places = [a, b]
        day.applyOrder([b, a])
        XCTAssertEqual(day.sortedPlaces.map(\.name), ["B", "A"])
        XCTAssertEqual([b.order, a.order], [0, 1])
    }

    func testTripPersistsAndDeletingCascades() throws {
        let container = try TestSupport.makeContainer()
        let context = container.mainContext
        let trip = Trip(destination: "Lisbon", startDate: .now, endDate: .now)
        let day = Day(date: .now)
        day.places = [Place(name: "A", category: .park, latitude: 1, longitude: 2, timeSlot: .morning)]
        trip.days = [day]
        context.insert(trip)
        try context.save()

        XCTAssertEqual(try context.fetch(FetchDescriptor<Trip>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Place>()).count, 1)

        context.delete(trip)
        try context.save()
        XCTAssertEqual(try context.fetch(FetchDescriptor<Day>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Place>()).count, 0)
    }

    func testSafetyBandRules() {
        XCTAssertEqual(SafetyBand(score: 90, confidence: .medium), .comfortable)
        XCTAssertEqual(SafetyBand(score: 75, confidence: .high), .comfortable)
        XCTAssertEqual(SafetyBand(score: 74, confidence: .high), .takeCare)
        XCTAssertEqual(SafetyBand(score: nil, confidence: .high), .limitedData)
        XCTAssertEqual(SafetyBand(score: 95, confidence: .low), .limitedData, "Low confidence hides the score")
    }

    func testGeoPointDistance() {
        let a = GeoPoint(latitude: 38.7075, longitude: -9.1364)
        XCTAssertEqual(a.distance(to: a), 0, accuracy: 0.001)
        // Praça do Comércio -> Belém Tower is roughly 6 km.
        let b = GeoPoint(latitude: 38.6916, longitude: -9.2160)
        XCTAssertEqual(a.distance(to: b), 7_100, accuracy: 600)
    }
}
