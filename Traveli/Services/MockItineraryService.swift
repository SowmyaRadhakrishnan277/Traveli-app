import Foundation

/// Deterministic stand-in for the future LLM-backed service.
/// Known cities use hand-written content; anything else gets placeholder stops
/// around the city centre, which is resolved through `PlacesService`.
struct MockItineraryService: ItineraryService {
    var placesService: PlacesService?
    /// Simulated network latency so loading states are visible. Use `.zero` in tests.
    var latency: Duration = .milliseconds(700)
    var calendar: Calendar = .current

    func generateItinerary(for request: ItineraryRequest) async throws -> [DayProposal] {
        let dates = try request.dayDates(calendar: calendar)
        if latency > .zero { try await Task.sleep(for: latency) }
        let template = try await resolveTemplate(for: request.destination)
        return dates.enumerated().map { index, date in
            DayProposal(date: date, places: template.proposals(forDay: index))
        }
    }

    private func resolveTemplate(for destination: String) async throws -> CityTemplate {
        if let known = MockCityCatalog.template(for: destination) { return known }
        guard let placesService else { throw ItineraryError.destinationNotFound }
        let hits: [PlaceSuggestion]
        do {
            hits = try await placesService.search(query: destination, near: nil)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ItineraryError.destinationLookupFailed
        }
        guard let centre = hits.first?.location else { throw ItineraryError.destinationNotFound }
        return MockCityCatalog.generic(around: centre)
    }
}
