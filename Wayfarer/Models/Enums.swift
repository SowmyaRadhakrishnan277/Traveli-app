import Foundation

/// Kind of place. Drives icons and the (mock) safety profile.
enum PlaceCategory: String, Codable, CaseIterable, Sendable {
    case landmark, museum, park, restaurant, cafe, market
    case viewpoint, nightlife, beach, transit, other
}

/// Part of the day a stop is planned for.
enum TimeSlot: String, Codable, CaseIterable, Sendable, Comparable {
    case morning, afternoon, evening

    /// Evening stops are scored with the "after dark" profile.
    var isNight: Bool { self == .evening }

    private var sortIndex: Int { TimeSlot.allCases.firstIndex(of: self) ?? 0 }
    static func < (lhs: TimeSlot, rhs: TimeSlot) -> Bool { lhs.sortIndex < rhs.sortIndex }
}

enum CommuteMode: String, Codable, CaseIterable, Sendable {
    case walk, transit, taxi
}

enum SafetyConfidence: String, Codable, CaseIterable, Sendable {
    case low, medium, high
}

/// Deliberately gentle wording: we never label a place "unsafe", because the
/// data is incomplete and biased. See README "Privacy and safety-score bias".
enum SafetyBand: String, Codable, CaseIterable, Sendable {
    case comfortable, takeCare, limitedData

    static let comfortableThreshold = 75

    /// Low confidence or a missing score always degrades to `limitedData`.
    init(score: Int?, confidence: SafetyConfidence) {
        guard let score, confidence != .low else {
            self = .limitedData
            return
        }
        self = score >= Self.comfortableThreshold ? .comfortable : .takeCare
    }
}
