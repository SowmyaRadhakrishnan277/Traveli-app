import Foundation
import SwiftData

@Model
final class Day {
    var date: Date
    var trip: Trip?

    @Relationship(deleteRule: .cascade, inverse: \Place.day)
    var places: [Place] = []

    init(date: Date) {
        self.date = date
    }

    /// Places in visiting order (relationships are unordered, so `Place.order` is the source of truth).
    var sortedPlaces: [Place] { places.sorted { $0.order < $1.order } }

    /// Rewrites `order` so it matches the given sequence (0, 1, 2, ...).
    func applyOrder(_ ordered: [Place]) {
        for (index, place) in ordered.enumerated() {
            place.order = index
        }
    }
}
