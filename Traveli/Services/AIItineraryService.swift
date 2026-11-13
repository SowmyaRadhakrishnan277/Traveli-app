import Foundation
#if canImport(FoundationModels)
import FoundationModels

// Structured output for guided generation: the model must fill these fields, so we never parse free text.

@available(iOS 26.0, *)
@Generable
struct AIDayPlan {
    @Guide(description: "Exactly three stops for the day: one morning, one afternoon, one evening, in that order.", .count(3))
    var stops: [AIStop]
}

@available(iOS 26.0, *)
@Generable
struct AIStop {
    @Guide(description: "Name of a real, well-known place exactly as it appears on Apple Maps. Never invent places.")
    var name: String

    @Guide(.anyOf(["landmark", "museum", "park", "restaurant", "cafe", "market", "viewpoint", "nightlife", "beach", "transit"]))
    var category: String

    @Guide(.anyOf(["morning", "afternoon", "evening"]))
    var timeSlot: String
}

/// Builds an itinerary with Apple's on-device language model (no network, no API key, nothing leaves the phone).
/// One model call per day keeps each request small, and every stop is verified on the map.
@available(iOS 26.0, *)
struct AIItineraryService: ItineraryService {
    let places: PlacesService
    var calendar: Calendar = .current

    private static let instructions = """
        You are a careful travel planner for solo women travellers. Plan one day at a time. \
        Prefer well-known, well-lit, busy places. Put quieter spots such as parks and viewpoints in the \
        morning or afternoon, and choose lively, populated areas for the evening. \
        Keep each day geographically compact so travel between stops is short. \
        Only suggest real places that exist on Apple Maps. Do not repeat places from earlier days.
        """

    func generateItinerary(for request: ItineraryRequest) async throws -> Itinerary {
        let dates = try request.dayDates(calendar: calendar)
        let availability = AIAvailability.current
        guard case .available = availability else {
            if case .unavailable(let reason) = availability { throw ItineraryError.aiUnavailable(reason: reason) }
            throw ItineraryError.aiFailed
        }

        let centre = try await resolveCentre(of: request.destination)
        let verifier = StopVerifier(places: places)
        var used = Set<String>()
        var days: [DayProposal] = []

        for (index, date) in dates.enumerated() {
            try Task.checkCancellation()
            let candidates = try await suggestStops(for: request, dayNumber: index + 1, of: dates.count, avoiding: used)
            let stops = await verifier.verify(candidates, destination: request.destination, centre: centre, excluding: used)
            // A day with fewer than two real places isn't a plan; let the caller fall back.
            guard stops.count >= 2 else { throw ItineraryError.aiFailed }
            used.formUnion(stops.map { StopVerifier.key($0.name) })
            days.append(DayProposal(date: date, places: stops))
        }
        return Itinerary(days: days, origin: .ai)
    }

    private func suggestStops(
        for request: ItineraryRequest, dayNumber: Int, of total: Int, avoiding used: Set<String>
    ) async throws -> [StopCandidate] {
        var prompt = "Plan day \(dayNumber) of \(total) in \(request.destination)."
        if !request.preferences.isEmpty {
            prompt += " The traveller's wishes: \(request.preferences)."
        }
        if !used.isEmpty {
            prompt += " Already planned, do not repeat: \(used.sorted().joined(separator: ", "))."
        }
        do {
            // A fresh session per day keeps the context window small.
            let session = LanguageModelSession(instructions: Self.instructions)
            let plan = try await session.respond(to: prompt, generating: AIDayPlan.self).content
            return plan.stops.map { StopCandidate(name: $0.name, category: $0.category, timeSlot: $0.timeSlot) }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Guardrails, context limits, unsupported language, rate limits...
            throw ItineraryError.aiFailed
        }
    }

    private func resolveCentre(of destination: String) async throws -> GeoPoint {
        let hits: [PlaceSuggestion]
        do {
            hits = try await places.search(query: destination, near: nil)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ItineraryError.destinationLookupFailed
        }
        guard let centre = hits.first?.location else { throw ItineraryError.destinationNotFound }
        return centre
    }
}
#endif
