import Foundation

struct SafetyQuery: Sendable, Hashable {
    var name: String
    var category: PlaceCategory
    var location: GeoPoint
    var timeSlot: TimeSlot
}

struct SafetyAssessment: Sendable, Equatable {
    var score: Int?
    var band: SafetyBand
    var reason: String
    var dayNote: String
    var nightNote: String
    var confidence: SafetyConfidence
    var sources: [String]

    static let limitedData = SafetyAssessment(
        score: nil,
        band: .limitedData,
        reason: "We don't have enough information about this place yet.",
        dayNote: "No daytime information available.",
        nightNote: "No after-dark information available.",
        confidence: .low,
        sources: []
    )
}

/// Scores a stop for a given time of day. Mock today; later a rule-based
/// formula over structured signals, with RAG-written, cited explanations.
protocol SafetyScoringService: Sendable {
    func assess(_ query: SafetyQuery) async -> SafetyAssessment
}
