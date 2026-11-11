import SwiftUI

// UI-only wording, icons and colours live here so the model layer stays free of presentation.

extension PlaceCategory {
    var title: String { rawValue.capitalized }

    var systemImage: String {
        switch self {
        case .landmark: "building.columns"
        case .museum: "paintpalette"
        case .park: "tree"
        case .restaurant: "fork.knife"
        case .cafe: "cup.and.saucer"
        case .market: "basket"
        case .viewpoint: "binoculars"
        case .nightlife: "moon.stars"
        case .beach: "beach.umbrella"
        case .transit: "tram"
        case .other: "mappin"
        }
    }
}

extension TimeSlot {
    var title: String { rawValue.capitalized }

    var systemImage: String {
        switch self {
        case .morning: "sunrise"
        case .afternoon: "sun.max"
        case .evening: "moon"
        }
    }
}

extension CommuteMode {
    var systemImage: String {
        switch self {
        case .walk: "figure.walk"
        case .transit: "tram.fill"
        case .taxi: "car.fill"
        }
    }

    var phrase: String {
        switch self {
        case .walk: "walk"
        case .transit: "by transit"
        case .taxi: "by taxi"
        }
    }
}

extension SafetyBand {
    var title: String {
        switch self {
        case .comfortable: "Comfortable"
        case .takeCare: "Take care"
        case .limitedData: "Limited data"
        }
    }

    var systemImage: String {
        switch self {
        case .comfortable: "checkmark.circle.fill"
        case .takeCare: "exclamationmark.triangle.fill"
        case .limitedData: "questionmark.circle.fill"
        }
    }

    /// Never the only signal: every use is paired with an icon and the band title.
    var color: Color {
        switch self {
        case .comfortable: .green
        case .takeCare: .orange
        case .limitedData: .gray
        }
    }
}

extension SafetyConfidence {
    var title: String { rawValue.capitalized }
}

extension Place {
    var badgeText: String {
        if let safetyScore, safetyBand != .limitedData {
            return "\(safetyBand.title) · \(safetyScore)/100"
        }
        return safetyBand.title
    }

    var commutePhrase: String {
        "\(commuteMinutes) min \(commuteMode.phrase) to next stop"
    }

    func accessibilitySummary(index: Int, isLast: Bool) -> String {
        var parts = [
            "Stop \(index + 1): \(name).",
            "\(category.title), \(timeSlot.title).",
            "Safety: \(safetyBand.title)" + (safetyScore.map { ", \($0) out of 100" } ?? "")
                + ", \(safetyConfidence.title) confidence.",
            safetyReason,
        ]
        if !isLast, commuteMinutes > 0 { parts.append(commutePhrase + ".") }
        return parts.joined(separator: " ")
    }
}

extension Day {
    func heading(number: Int) -> String {
        "Day \(number) · " + date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }
}
