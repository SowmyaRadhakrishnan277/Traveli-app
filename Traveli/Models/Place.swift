import Foundation
import SwiftData

@Model
final class Place {
    var name: String
    var category: PlaceCategory
    var latitude: Double
    var longitude: Double
    var timeSlot: TimeSlot
    /// Position within the day (0-based). Needed because relationships are unordered.
    var order: Int

    /// Estimated travel time to the *next* stop. 0 for the last stop of a day.
    var commuteMinutes: Int
    var commuteMode: CommuteMode

    /// `nil` means "not enough data" - never shown as a number.
    var safetyScore: Int?
    var safetyBand: SafetyBand
    var safetyReason: String
    var safetyDayNote: String
    var safetyNightNote: String
    var safetyConfidence: SafetyConfidence
    var sources: [String]

    var day: Day?

    init(
        name: String,
        category: PlaceCategory,
        latitude: Double,
        longitude: Double,
        timeSlot: TimeSlot,
        order: Int = 0,
        commuteMinutes: Int = 0,
        commuteMode: CommuteMode = .walk,
        safetyScore: Int? = nil,
        safetyBand: SafetyBand = .limitedData,
        safetyReason: String = "",
        safetyDayNote: String = "",
        safetyNightNote: String = "",
        safetyConfidence: SafetyConfidence = .low,
        sources: [String] = []
    ) {
        self.name = name
        self.category = category
        self.latitude = latitude
        self.longitude = longitude
        self.timeSlot = timeSlot
        self.order = order
        self.commuteMinutes = commuteMinutes
        self.commuteMode = commuteMode
        self.safetyScore = safetyScore
        self.safetyBand = safetyBand
        self.safetyReason = safetyReason
        self.safetyDayNote = safetyDayNote
        self.safetyNightNote = safetyNightNote
        self.safetyConfidence = safetyConfidence
        self.sources = sources
    }

    var location: GeoPoint { GeoPoint(latitude: latitude, longitude: longitude) }

    /// Copies the output of a `SafetyScoringService` onto this place.
    func apply(_ assessment: SafetyAssessment) {
        safetyScore = assessment.score
        safetyBand = assessment.band
        safetyReason = assessment.reason
        safetyDayNote = assessment.dayNote
        safetyNightNote = assessment.nightNote
        safetyConfidence = assessment.confidence
        sources = assessment.sources
    }
}
