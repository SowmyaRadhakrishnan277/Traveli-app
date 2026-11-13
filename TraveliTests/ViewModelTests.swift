import Foundation
import SwiftData
import XCTest
@testable import Traveli

@MainActor
final class TripPlannerTests: XCTestCase {
    func testBuildTripHasDaysPlacesSafetyAndCommutes() async throws {
        let trip = try await TestSupport.planner.buildTrip(
            destination: " Lisbon ", startDate: TestSupport.date(2026, 3, 1), endDate: TestSupport.date(2026, 3, 2)
        )
        XCTAssertEqual(trip.destination, "Lisbon")
        XCTAssertEqual(trip.sortedDays.count, 2)
        for day in trip.sortedDays {
            let places = day.sortedPlaces
            XCTAssertEqual(places.count, 3)
            XCTAssertTrue(places.allSatisfy { !$0.safetyReason.isEmpty })
            XCTAssertTrue(places.dropLast().allSatisfy { $0.commuteMinutes > 0 })
            XCTAssertEqual(places.last?.commuteMinutes, 0)
        }
    }
}

@MainActor
final class ItineraryViewModelTests: XCTestCase {
    private func makeViewModel() async throws -> (ItineraryViewModel, ModelContainer) {
        let container = try TestSupport.makeContainer()
        let trip = try await TestSupport.planner.buildTrip(
            destination: "Lisbon", startDate: TestSupport.date(2026, 3, 1), endDate: TestSupport.date(2026, 3, 1)
        )
        container.mainContext.insert(trip)
        try container.mainContext.save()
        return (ItineraryViewModel(trip: trip, planner: TestSupport.planner), container)
    }

    func testAddAppendsPlaceAndRecalculatesPreviousCommute() async throws {
        let (vm, _) = try await makeViewModel()
        let before = vm.places.last!.commuteMinutes
        XCTAssertEqual(before, 0)

        await vm.add(.stub("New Café", lat: 38.75, lon: -9.10), slot: .evening)

        XCTAssertEqual(vm.places.count, 4)
        XCTAssertEqual(vm.places.last?.name, "New Café")
        XCTAssertGreaterThan(vm.places[2].commuteMinutes, 0, "Old last stop now has a next stop")
        XCTAssertEqual(vm.places.last?.commuteMinutes, 0)
    }

    func testAddedUnknownCategoryGetsLimitedData() async throws {
        let (vm, _) = try await makeViewModel()
        await vm.add(.stub("Mystery", category: .other), slot: .afternoon)
        XCTAssertEqual(vm.places.last?.safetyBand, .limitedData)
        XCTAssertNil(vm.places.last?.safetyScore)
    }

    func testDeleteKeepsOrderContiguousAndPersists() async throws {
        let (vm, container) = try await makeViewModel()
        let survivors = [vm.places[0].name, vm.places[2].name]
        vm.delete(at: IndexSet(integer: 1))
        await vm.pendingRecalculation?.value

        XCTAssertEqual(vm.places.map(\.name), survivors)
        XCTAssertEqual(vm.places.map(\.order), [0, 1])
        XCTAssertEqual(vm.places.last?.commuteMinutes, 0)
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<Place>()).count, 2)
    }

    func testMoveReordersAndRecalculatesCommutes() async throws {
        let (vm, _) = try await makeViewModel()
        let names = vm.places.map(\.name)
        vm.move(from: IndexSet(integer: 0), to: 3) // first place to the end
        await vm.pendingRecalculation?.value

        XCTAssertEqual(vm.places.map(\.name), [names[1], names[2], names[0]])
        XCTAssertEqual(vm.places.last?.commuteMinutes, 0)
        XCTAssertTrue(vm.places.dropLast().allSatisfy { $0.commuteMinutes > 0 })
    }

    func testMapRegionFramesAllPlaces() async throws {
        let (vm, _) = try await makeViewModel()
        let region = try XCTUnwrap(vm.mapRegion)
        for place in vm.places {
            XCTAssertLessThanOrEqual(abs(place.latitude - region.center.latitude), region.span.latitudeDelta / 2)
            XCTAssertLessThanOrEqual(abs(place.longitude - region.center.longitude), region.span.longitudeDelta / 2)
        }
    }
}

@MainActor
final class TripFormViewModelTests: XCTestCase {
    func testCannotSubmitWithoutDestination() {
        let vm = TripFormViewModel(planner: TestSupport.planner)
        XCTAssertFalse(vm.canSubmit)
        vm.destination = "Lisbon"
        XCTAssertTrue(vm.canSubmit)
    }

    func testEndDateFollowsStartDate() {
        let vm = TripFormViewModel(planner: TestSupport.planner)
        vm.startDate = vm.endDate.addingTimeInterval(86_400 * 3)
        vm.startDateChanged()
        XCTAssertEqual(vm.endDate, vm.startDate)
    }

    func testGenerateSavesTrip() async throws {
        let container = try TestSupport.makeContainer()
        let vm = TripFormViewModel(planner: TestSupport.planner)
        vm.destination = "Paris"
        let trip = await vm.generate(in: container.mainContext)
        XCTAssertNotNil(trip)
        XCTAssertEqual(vm.state, .idle)
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<Trip>()).count, 1)
    }

    func testFailureSurfacesMessageAndSavesNothing() async throws {
        let container = try TestSupport.makeContainer()
        let vm = TripFormViewModel(planner: TestSupport.planner) // placesService is nil
        vm.destination = "Atlantis"
        let trip = await vm.generate(in: container.mainContext)
        XCTAssertNil(trip)
        XCTAssertEqual(vm.state, .failed(ItineraryError.destinationNotFound.localizedDescription))
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<Trip>()).count, 0)
    }
}

@MainActor
final class PlaceSearchViewModelTests: XCTestCase {
    func testStates() async {
        var vm = PlaceSearchViewModel(service: StubPlacesService(results: [.stub("A")]), near: nil, debounce: .zero)
        await vm.search()
        XCTAssertEqual(vm.state, .idle)

        vm.query = "a"
        await vm.search()
        XCTAssertEqual(vm.state, .results([.stub("A")]))

        vm = PlaceSearchViewModel(service: StubPlacesService(results: []), near: nil, debounce: .zero)
        vm.query = "zzz"
        await vm.search()
        XCTAssertEqual(vm.state, .empty)

        vm = PlaceSearchViewModel(service: StubPlacesService(error: StubError()), near: nil, debounce: .zero)
        vm.query = "a"
        await vm.search()
        if case .failed = vm.state {} else { XCTFail("Expected failed, got \(vm.state)") }
    }
}
