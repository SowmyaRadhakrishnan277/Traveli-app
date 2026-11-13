#if DEBUG
import Foundation
import SwiftData

/// In-memory sample data for SwiftUI previews.
@MainActor
enum PreviewData {
    static let container: ModelContainer = {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(for: Trip.self, Day.self, Place.self, configurations: config)
    }()

    @discardableResult
    static func sampleTrip() -> Trip {
        let start = Calendar.current.startOfDay(for: .now)
        let trip = Trip(destination: "Lisbon", startDate: start,
                        endDate: Calendar.current.date(byAdding: .day, value: 1, to: start)!)
        let day = Day(date: start)
        day.places = [
            Place(name: "Jardim da Estrela", category: .park, latitude: 38.7133, longitude: -9.1592,
                  timeSlot: .morning, order: 0, commuteMinutes: 18, commuteMode: .transit,
                  safetyScore: 78, safetyBand: .comfortable,
                  safetyReason: "Open space that is lively by day but isolated after dark.",
                  safetyDayNote: "Joggers and families; generally relaxed.",
                  safetyNightNote: "Often poorly lit and empty.",
                  safetyConfidence: .medium, sources: ["Demo data only"]),
            Place(name: "Belém Tower", category: .landmark, latitude: 38.6916, longitude: -9.2160,
                  timeSlot: .afternoon, order: 1, commuteMinutes: 22, commuteMode: .transit,
                  safetyScore: 85, safetyBand: .comfortable,
                  safetyReason: "Popular, well-visited area with regular foot traffic.",
                  safetyConfidence: .medium),
            Place(name: "Bairro Alto", category: .nightlife, latitude: 38.7129, longitude: -9.1458,
                  timeSlot: .evening, order: 2,
                  safetyScore: 58, safetyBand: .takeCare,
                  safetyReason: "Crowded late, with drinks and noise. Stay aware.",
                  safetyConfidence: .medium),
        ]
        trip.days = [day, Day(date: Calendar.current.date(byAdding: .day, value: 1, to: start)!)]
        container.mainContext.insert(trip)
        return trip
    }
}
#endif
