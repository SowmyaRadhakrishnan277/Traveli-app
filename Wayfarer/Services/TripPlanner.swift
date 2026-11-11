import Foundation

/// Orchestrates the three services into SwiftData models. The only place that
/// knows how an itinerary, a safety assessment and a commute fit together.
struct TripPlanner: Sendable {
    let itinerary: ItineraryService
    let safety: SafetyScoringService
    let routing: RoutingService

    /// Builds an (uninserted) trip. The caller inserts it into a `ModelContext`.
    @MainActor
    func buildTrip(destination: String, startDate: Date, endDate: Date) async throws -> Trip {
        let request = ItineraryRequest(
            destination: destination.trimmingCharacters(in: .whitespacesAndNewlines),
            startDate: startDate,
            endDate: endDate
        )
        let proposals = try await itinerary.generateItinerary(for: request)
        let trip = Trip(destination: request.destination, startDate: startDate, endDate: endDate)
        for proposal in proposals {
            let day = Day(date: proposal.date)
            for (index, stop) in proposal.places.enumerated() {
                let place = await makePlace(
                    name: stop.name, category: stop.category, location: stop.location,
                    timeSlot: stop.timeSlot, order: index
                )
                day.places.append(place)
            }
            await recalculateCommutes(for: day)
            trip.days.append(day)
        }
        return trip
    }

    @MainActor
    func makePlace(
        name: String, category: PlaceCategory, location: GeoPoint, timeSlot: TimeSlot, order: Int
    ) async -> Place {
        let assessment = await safety.assess(
            SafetyQuery(name: name, category: category, location: location, timeSlot: timeSlot)
        )
        let place = Place(
            name: name, category: category,
            latitude: location.latitude, longitude: location.longitude,
            timeSlot: timeSlot, order: order
        )
        place.apply(assessment)
        return place
    }

    /// Recomputes "minutes to next stop" for every place in the day's current order.
    @MainActor
    func recalculateCommutes(for day: Day) async {
        let places = day.sortedPlaces
        for (index, place) in places.enumerated() {
            guard index + 1 < places.count else {
                place.commuteMinutes = 0
                continue
            }
            let estimate = await routing.estimate(from: place.location, to: places[index + 1].location)
            // A newer edit supersedes this pass; don't overwrite with stale results.
            guard !Task.isCancelled else { return }
            place.commuteMinutes = estimate.minutes
            place.commuteMode = estimate.mode
        }
    }
}
