import Foundation
@testable import Traveli

/// Cyclic Latin square: row r lists the items starting at r and wrapping around, so across
/// n consecutive rows every item appears in every position exactly once (lecture L5, counterbalancing).
enum LatinSquare {
    static func order<T>(_ items: [T], row: Int) -> [T] {
        guard !items.isEmpty else { return [] }
        let n = items.count
        return (0..<n).map { items[(row % n + $0) % n] }
    }
}

struct ExperimentDestination: Equatable {
    var name: String
    var region: String

    /// Spread across regions on purpose: the same data later feeds a fairness audit (lecture L13).
    static let defaults: [ExperimentDestination] = [
        .init(name: "Lisbon", region: "Europe"),
        .init(name: "Tokyo", region: "Asia"),
        .init(name: "Mexico City", region: "Americas"),
        .init(name: "Cape Town", region: "Africa"),
        .init(name: "Paris", region: "Europe"),
        .init(name: "Chennai", region: "Asia"),
        .init(name: "Buenos Aires", region: "Americas"),
        .init(name: "Sydney", region: "Oceania"),
        .init(name: "Reykjavik", region: "Europe"),
        .init(name: "Istanbul", region: "Europe"),
        .init(name: "Marrakech", region: "Africa"),
        .init(name: "Nairobi", region: "Africa"),
        .init(name: "Bangkok", region: "Asia"),
        .init(name: "Seoul", region: "Asia"),
        .init(name: "Lima", region: "Americas"),
        .init(name: "Toronto", region: "Americas"),
        .init(name: "Rome", region: "Europe"),
        .init(name: "Auckland", region: "Oceania"),
        .init(name: "Dubai", region: "Asia"),
        .init(name: "Berlin", region: "Europe"),
    ]
}

/// One generated day under one prompt variant: the unit written to the CSV.
struct ExperimentRow: Equatable {
    var destination: String
    var region: String
    var variant: String
    /// 1-based position of this variant within the destination's counterbalanced order.
    var position: Int
    var metrics: DayMetrics

    static let header = "destination,region,variant,position,day,suggested,verified,rejected_not_found,rejected_duplicate,search_errors,verified_rate,mean_leg_km,latency_s,usable"

    var csvLine: String {
        [
            Self.escape(destination), Self.escape(region), Self.escape(variant),
            "\(position)", "\(metrics.dayNumber)", "\(metrics.suggested)", "\(metrics.verified)",
            "\(metrics.rejectedNotFound)", "\(metrics.rejectedDuplicate)", "\(metrics.searchErrors)",
            String(format: "%.4f", metrics.verifiedRate),
            metrics.meanLegMetres.map { String(format: "%.4f", $0 / 1000) } ?? "",
            String(format: "%.3f", metrics.seconds),
            metrics.isUsable ? "1" : "0",
        ].joined(separator: ",")
    }

    static func csv(_ rows: [ExperimentRow]) -> String {
        ([header] + rows.map(\.csvLine)).joined(separator: "\n") + "\n"
    }

    private static func escape(_ field: String) -> String {
        field.contains(where: { ",\"\n".contains($0) }) ? "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : field
    }
}

/// Within-subjects experiment: every destination ("subject") is planned under every prompt variant,
/// in an order rotated per destination so order effects (warm-up, throttling) are balanced.
struct ExperimentRunner {
    var destinations: [ExperimentDestination]
    var variants: [PromptVariant]
    var daysPerTrip: Int
    var makeService: (PromptVariant) -> AIItineraryService
    var calendar: Calendar = .current
    /// Pause between trials, to stay under the map service's rate limit.
    var pauseBetweenTrials: Duration = .zero

    func run(progress: (String) -> Void = { _ in }) async throws -> [ExperimentRow] {
        var rows: [ExperimentRow] = []
        let start = calendar.date(from: DateComponents(year: 2027, month: 3, day: 1))!
        let end = calendar.date(byAdding: .day, value: daysPerTrip - 1, to: start)!

        for (index, destination) in destinations.enumerated() {
            for (offset, variant) in LatinSquare.order(variants, row: index).enumerated() {
                let request = ItineraryRequest(destination: destination.name, startDate: start, endDate: end)
                if pauseBetweenTrials > .zero { try await Task.sleep(for: pauseBetweenTrials) }
                do {
                    let report = try await makeService(variant).run(for: request, stopOnFailure: false)
                    rows += report.days.map {
                        ExperimentRow(destination: destination.name, region: destination.region,
                                      variant: variant.id, position: offset + 1, metrics: $0)
                    }
                    let verified = report.days.map(\.verified).reduce(0, +)
                    let suggested = report.days.map(\.suggested).reduce(0, +)
                    let errors = report.days.map(\.searchErrors).reduce(0, +)
                    progress("\(destination.name) [\(variant.id)] position \(offset + 1): \(verified)/\(suggested) verified, \(errors) search errors")
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    progress("\(destination.name) [\(variant.id)] SKIPPED: \(error.localizedDescription)")
                }
            }
        }
        return rows
    }
}
