import Foundation

/// Tries the AI service first and quietly falls back to the sample generator, telling the user why.
/// Input problems (bad dates, unknown destination) are never swallowed.
struct FallbackItineraryService: ItineraryService {
    var primary: ItineraryService?
    var fallback: ItineraryService

    func generateItinerary(for request: ItineraryRequest) async throws -> Itinerary {
        // Without a primary service (older iOS) the reason comes from the system check.
        var notice = primary == nil ? unavailableReason : ""
        if let primary {
            do {
                return try await primary.generateItinerary(for: request)
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as ItineraryError {
                if error.isValidation { throw error }
                notice = error.errorDescription ?? notice
            } catch {
                notice = ItineraryError.aiFailed.errorDescription ?? notice
            }
        }
        var result = try await fallback.generateItinerary(for: request)
        result.notice = notice.isEmpty ? "Sample itinerary." : "\(notice) Showing a sample itinerary instead."
        return result
    }

    private var unavailableReason: String {
        if case .unavailable(let reason) = AIAvailability.current { return reason }
        return ""
    }
}
