import Foundation

struct ItineraryRequest: Sendable, Equatable {
    var destination: String
    var startDate: Date
    var endDate: Date
    /// Optional free-text wishes, e.g. "love food markets, quiet mornings". Only used by AI services.
    var preferences: String = ""

    static let maxDays = 14

    /// Validates the request and returns one start-of-day date per trip day.
    func dayDates(calendar: Calendar = .current) throws -> [Date] {
        guard !destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ItineraryError.emptyDestination
        }
        let start = calendar.startOfDay(for: startDate)
        let end = calendar.startOfDay(for: endDate)
        guard end >= start else { throw ItineraryError.invalidDateRange }
        let count = (calendar.dateComponents([.day], from: start, to: end).day ?? 0) + 1
        guard count <= Self.maxDays else { throw ItineraryError.tooLong(maxDays: Self.maxDays) }
        return (0..<count).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }
}

/// A suggested stop. Plain values, so a future LLM-backed service can return
/// decoded JSON here and the app can verify each stop via MapKit before saving.
struct PlaceProposal: Sendable, Hashable {
    var name: String
    var category: PlaceCategory
    var location: GeoPoint
    var timeSlot: TimeSlot
}

struct DayProposal: Sendable, Hashable {
    var date: Date
    var places: [PlaceProposal]
}

/// Where an itinerary came from, so the UI can be honest about it.
enum ItineraryOrigin: String, Sendable, Equatable {
    case ai
    case sample
}

struct Itinerary: Sendable, Equatable {
    var days: [DayProposal]
    var origin: ItineraryOrigin
    /// Shown to the user, e.g. why AI wasn't used.
    var notice: String = ""
}

enum ItineraryError: LocalizedError, Equatable {
    case emptyDestination
    case invalidDateRange
    case tooLong(maxDays: Int)
    case destinationNotFound
    case destinationLookupFailed
    case aiUnavailable(reason: String)
    case aiFailed

    /// Input problems the user must fix; never worth falling back from.
    var isValidation: Bool {
        switch self {
        case .emptyDestination, .invalidDateRange, .tooLong, .destinationNotFound: true
        default: false
        }
    }

    var errorDescription: String? {
        switch self {
        case .emptyDestination: "Enter a destination to get started."
        case .invalidDateRange: "The end date must be on or after the start date."
        case .tooLong(let max): "Trips are limited to \(max) days for now."
        case .destinationNotFound: "We couldn't find that destination. Try a nearby city name."
        case .destinationLookupFailed: "We couldn't look up that destination. Check your connection and try again."
        case .aiUnavailable(let reason): reason
        case .aiFailed: "The AI couldn't build a reliable plan this time."
        }
    }
}

/// Produces a draft itinerary: on-device AI when available, otherwise a sample.
/// A server-backed LLM can slot in here later (no API keys ever ship in the app).
protocol ItineraryService: Sendable {
    func generateItinerary(for request: ItineraryRequest) async throws -> Itinerary
}
