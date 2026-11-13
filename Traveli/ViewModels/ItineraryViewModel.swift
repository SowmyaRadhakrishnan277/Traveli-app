import Foundation
import MapKit
import Observation
import SwiftData
import SwiftUI

@MainActor
@Observable
final class ItineraryViewModel {
    let trip: Trip
    var selectedDayIndex = 0
    var errorMessage: String?
    private(set) var isWorking = false

    /// Exposed so tests can await the background commute recalculation.
    private(set) var pendingRecalculation: Task<Void, Never>?

    private let planner: TripPlanner

    init(trip: Trip, planner: TripPlanner) {
        self.trip = trip
        self.planner = planner
    }

    var days: [Day] { trip.sortedDays }

    var selectedDay: Day? {
        let days = days
        guard days.indices.contains(selectedDayIndex) else { return days.first }
        return days[selectedDayIndex]
    }

    var places: [Place] { selectedDay?.sortedPlaces ?? [] }

    /// Changes whenever the map should re-frame itself.
    var mapFitToken: String {
        "\(selectedDayIndex)|" + places.map { "\($0.name)@\($0.latitude),\($0.longitude)" }.joined(separator: ";")
    }

    /// A region that frames all of the selected day's stops, with padding.
    var mapRegion: MKCoordinateRegion? {
        let places = places
        guard let first = places.first else { return nil }
        var minLat = first.latitude, maxLat = first.latitude
        var minLon = first.longitude, maxLon = first.longitude
        for place in places {
            minLat = min(minLat, place.latitude); maxLat = max(maxLat, place.latitude)
            minLon = min(minLon, place.longitude); maxLon = max(maxLon, place.longitude)
        }
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
            span: MKCoordinateSpan(
                latitudeDelta: max((maxLat - minLat) * 1.5, 0.01),
                longitudeDelta: max((maxLon - minLon) * 1.5, 0.01)
            )
        )
    }

    // MARK: - Editing

    /// Adds a searched place to the end of the selected day.
    func add(_ suggestion: PlaceSuggestion, slot: TimeSlot) async {
        guard let day = selectedDay else { return }
        isWorking = true
        defer { isWorking = false }
        let place = await planner.makePlace(
            name: suggestion.name, category: suggestion.category, location: suggestion.location,
            timeSlot: slot, order: day.places.count
        )
        day.places.append(place)
        saveAndRecalculate(day)
        await pendingRecalculation?.value
    }

    func delete(at offsets: IndexSet) {
        guard let day = selectedDay else { return }
        let sorted = day.sortedPlaces
        let removed = offsets.map { sorted[$0] }
        let removedIDs = Set(removed.map(\.persistentModelID))
        day.applyOrder(sorted.filter { !removedIDs.contains($0.persistentModelID) })
        day.places.removeAll { removedIDs.contains($0.persistentModelID) }
        removed.forEach { trip.modelContext?.delete($0) }
        saveAndRecalculate(day)
    }

    func move(from source: IndexSet, to destination: Int) {
        guard let day = selectedDay else { return }
        var ordered = day.sortedPlaces
        ordered.move(fromOffsets: source, toOffset: destination)
        day.applyOrder(ordered)
        saveAndRecalculate(day)
    }

    // MARK: - Private

    /// Persists immediately (order is correct right away), then refreshes commutes in the background.
    private func saveAndRecalculate(_ day: Day) {
        save()
        pendingRecalculation?.cancel()
        pendingRecalculation = Task { [planner] in
            self.isWorking = true
            await planner.recalculateCommutes(for: day)
            guard !Task.isCancelled else { return }
            self.save()
            self.isWorking = false
        }
    }

    private func save() {
        do {
            try trip.modelContext?.save()
        } catch {
            errorMessage = "Couldn't save your changes. \(error.localizedDescription)"
        }
    }
}
