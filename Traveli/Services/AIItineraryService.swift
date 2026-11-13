import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Asks a language model for one day's candidate stops. A protocol so the pipeline around
/// the model (verification, metrics, fallback) is testable without Apple Intelligence.
protocol StopSuggester: Sendable {
    func suggestStops(prompt: String, instructions: String) async throws -> [StopCandidate]
}

/// Quality measurements for one generated day. The raw material for prompt experiments.
struct DayMetrics: Sendable, Equatable {
    var dayNumber: Int
    var suggested: Int
    var verified: Int
    var rejectedNotFound: Int
    var rejectedDuplicate: Int
    /// Failed map lookups. A day with any is unreliable as model-quality data.
    var searchErrors: Int = 0
    /// Mean straight-line distance between consecutive verified stops, in metres. nil with fewer than 2 stops.
    var meanLegMetres: Double?
    /// Wall-clock time for the model call plus map verification.
    var seconds: Double

    /// Share of the model's suggestions that were real, new places.
    var verifiedRate: Double { suggested == 0 ? 0 : Double(verified) / Double(suggested) }
    /// A day needs at least two real stops to count as a plan.
    var isUsable: Bool { verified >= 2 }
}

struct GenerationReport: Sendable {
    var variant: PromptVariant
    var days: [DayMetrics]
    /// nil when any day was unusable.
    var itinerary: Itinerary?
}

/// Builds an itinerary with a language model (Apple's on-device model in the app), one call per day to
/// keep each request small, and verifies every stop on the map.
struct AIItineraryService: ItineraryService {
    let places: PlacesService
    let suggester: StopSuggester
    var variant: PromptVariant = .baseline
    var availability: @Sendable () -> AIAvailability = { AIAvailability.current }
    var calendar: Calendar = .current

    func generateItinerary(for request: ItineraryRequest) async throws -> Itinerary {
        let report = try await run(for: request)
        guard let itinerary = report.itinerary else { throw ItineraryError.aiFailed }
        return itinerary
    }

    /// Generates and measures. With `stopOnFailure: false` every day is attempted even after an
    /// unusable one, so experiments get complete data.
    func run(for request: ItineraryRequest, stopOnFailure: Bool = true) async throws -> GenerationReport {
        let dates = try request.dayDates(calendar: calendar)
        if case .unavailable(let reason) = availability() {
            throw ItineraryError.aiUnavailable(reason: reason)
        }

        let centre = try await resolveCentre(of: request.destination)
        let verifier = StopVerifier(places: places)
        let clock = ContinuousClock()
        var used = Set<String>()
        var days: [DayProposal] = []
        var metrics: [DayMetrics] = []
        var failed = false

        for (index, date) in dates.enumerated() {
            try Task.checkCancellation()
            let started = clock.now

            var candidates: [StopCandidate] = []
            do {
                candidates = try await suggester.suggestStops(
                    prompt: Self.prompt(for: request, dayNumber: index + 1, of: dates.count, avoiding: used),
                    instructions: variant.instructions
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                candidates = [] // guardrails, context limits, rate limits...: counts as an unusable day
            }
            let (stops, stats) = await verifier.verifyWithStats(
                candidates, destination: request.destination, centre: centre, excluding: used
            )

            let elapsed = clock.now - started
            metrics.append(DayMetrics(
                dayNumber: index + 1,
                suggested: stats.attempted,
                verified: stats.kept,
                rejectedNotFound: stats.rejectedNotFound,
                rejectedDuplicate: stats.rejectedDuplicate,
                searchErrors: stats.searchErrors,
                meanLegMetres: Self.meanLeg(of: stops),
                seconds: Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
            ))

            guard stops.count >= 2 else {
                failed = true
                if stopOnFailure { break }
                continue
            }
            used.formUnion(stops.map { StopVerifier.key($0.name) })
            days.append(DayProposal(date: date, places: stops))
        }
        return GenerationReport(
            variant: variant,
            days: metrics,
            itinerary: failed ? nil : Itinerary(days: days, origin: .ai)
        )
    }

    // MARK: - Helpers

    static func prompt(for request: ItineraryRequest, dayNumber: Int, of total: Int, avoiding used: Set<String>) -> String {
        var prompt = "Plan day \(dayNumber) of \(total) in \(request.destination)."
        if !request.preferences.isEmpty {
            prompt += " The traveller's wishes: \(request.preferences)."
        }
        if !used.isEmpty {
            prompt += " Already planned, do not repeat: \(used.sorted().joined(separator: ", "))."
        }
        return prompt
    }

    static func meanLeg(of stops: [PlaceProposal]) -> Double? {
        guard stops.count >= 2 else { return nil }
        let legs = zip(stops, stops.dropFirst()).map { $0.location.distance(to: $1.location) }
        return legs.reduce(0, +) / Double(legs.count)
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

#if canImport(FoundationModels)

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

/// Apple's on-device model: no network, no API key, nothing leaves the phone.
@available(iOS 26.0, *)
struct FoundationModelsStopSuggester: StopSuggester {
    func suggestStops(prompt: String, instructions: String) async throws -> [StopCandidate] {
        do {
            // A fresh session per day keeps the context window small and trials independent.
            let session = LanguageModelSession(instructions: instructions)
            let plan = try await session.respond(to: prompt, generating: AIDayPlan.self).content
            return plan.stops.map { StopCandidate(name: $0.name, category: $0.category, timeSlot: $0.timeSlot) }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ItineraryError.aiFailed
        }
    }
}
#endif
