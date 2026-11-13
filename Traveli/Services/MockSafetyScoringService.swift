import Foundation

/// Category-based demo scores. NOT a real assessment of any place.
struct MockSafetyScoringService: SafetyScoringService {
    private struct Profile {
        let day: Int
        let night: Int
        let reason: String
        let dayNote: String
        let nightNote: String
    }

    func assess(_ query: SafetyQuery) async -> SafetyAssessment {
        guard let profile = Self.profiles[query.category] else { return .limitedData }
        let score = query.timeSlot.isNight ? profile.night : profile.day
        let confidence = SafetyConfidence.medium
        return SafetyAssessment(
            score: score,
            band: SafetyBand(score: score, confidence: confidence),
            reason: profile.reason,
            dayNote: profile.dayNote,
            nightNote: profile.nightNote,
            confidence: confidence,
            sources: ["Demo data only - not a real assessment"]
        )
    }

    private static let profiles: [PlaceCategory: Profile] = [
        .landmark: Profile(day: 85, night: 66,
            reason: "Popular, well-visited area with regular foot traffic.",
            dayNote: "Busy with visitors and staff; easy to find help.",
            nightNote: "Quieter after the crowds leave; stick to well-lit routes."),
        .museum: Profile(day: 90, night: 50,
            reason: "Staffed venue with security during opening hours.",
            dayNote: "Open hours are staffed and busy.",
            nightNote: "Usually closed; surrounding streets can be empty."),
        .park: Profile(day: 78, night: 45,
            reason: "Open space that is lively by day but isolated after dark.",
            dayNote: "Joggers and families; generally relaxed.",
            nightNote: "Often poorly lit and empty. Consider avoiding."),
        .restaurant: Profile(day: 82, night: 70,
            reason: "Busy, staffed venue; the walk home matters most.",
            dayNote: "Lunch crowds and good visibility.",
            nightNote: "Lively until late; plan how you'll get back."),
        .cafe: Profile(day: 88, night: 62,
            reason: "Small, staffed venue in a typically active street.",
            dayNote: "Active street and regular customers.",
            nightNote: "Many close early, leaving the street quiet."),
        .market: Profile(day: 80, night: 55,
            reason: "Crowded in the day; watch for pickpockets.",
            dayNote: "Busy and social; keep bags zipped and in front.",
            nightNote: "Stalls pack up and the area empties out."),
        .viewpoint: Profile(day: 80, night: 52,
            reason: "Scenic spot that can be remote and quiet.",
            dayNote: "Popular for photos; usually other visitors around.",
            nightNote: "Can be secluded; go with others or choose busier times."),
        .nightlife: Profile(day: 70, night: 58,
            reason: "Crowded late, with drinks and noise. Stay aware.",
            dayNote: "Mostly closed and quiet in the daytime.",
            nightNote: "Busy and noisy; watch drinks and plan a safe ride home."),
        .beach: Profile(day: 80, night: 40,
            reason: "Fine in daylight; very isolated at night.",
            dayNote: "Lifeguards and families in season.",
            nightNote: "Dark and empty. Best avoided alone."),
        .transit: Profile(day: 72, night: 55,
            reason: "Busy hub; crowds can attract opportunistic theft.",
            dayNote: "Frequent services and many people about.",
            nightNote: "Fewer services and fewer people; wait in lit, staffed areas."),
    ]
}
