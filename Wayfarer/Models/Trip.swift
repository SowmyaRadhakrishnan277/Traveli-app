import Foundation
import SwiftData

@Model
final class Trip {
    @Attribute(.unique) var id: UUID
    var destination: String
    var startDate: Date
    var endDate: Date
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \Day.trip)
    var days: [Day] = []

    init(id: UUID = UUID(), destination: String, startDate: Date, endDate: Date, createdAt: Date = .now) {
        self.id = id
        self.destination = destination
        self.startDate = startDate
        self.endDate = endDate
        self.createdAt = createdAt
    }

    /// SwiftData relationships are unordered, so always read days through this.
    var sortedDays: [Day] { days.sorted { $0.date < $1.date } }
    var placeCount: Int { days.reduce(0) { $0 + $1.places.count } }
}
