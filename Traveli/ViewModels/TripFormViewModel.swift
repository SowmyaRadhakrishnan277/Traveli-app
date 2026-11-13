import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class TripFormViewModel {
    enum LoadState: Equatable {
        case idle
        case loading
        case failed(String)
    }

    var destination = ""
    var startDate: Date
    var endDate: Date
    private(set) var state: LoadState = .idle

    private let planner: TripPlanner

    init(planner: TripPlanner, today: Date = .now, calendar: Calendar = .current) {
        self.planner = planner
        let start = calendar.startOfDay(for: today)
        self.startDate = start
        self.endDate = calendar.date(byAdding: .day, value: 2, to: start) ?? start
    }

    var isLoading: Bool { state == .loading }

    /// Why the form can't be submitted yet (shown inline), or nil when valid.
    var validationMessage: String? {
        let request = ItineraryRequest(destination: destination, startDate: startDate, endDate: endDate)
        do {
            _ = try request.dayDates()
            return nil
        } catch {
            return destination.trimmingCharacters(in: .whitespaces).isEmpty ? nil : error.localizedDescription
        }
    }

    var canSubmit: Bool {
        !isLoading
            && !destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && validationMessage == nil
    }

    /// Keeps the end date from falling before the start date.
    func startDateChanged() {
        if endDate < startDate { endDate = startDate }
    }

    /// Generates, saves and returns the new trip, or nil after setting `state` to `.failed`.
    func generate(in context: ModelContext) async -> Trip? {
        guard canSubmit else { return nil }
        state = .loading
        do {
            let trip = try await planner.buildTrip(destination: destination, startDate: startDate, endDate: endDate)
            context.insert(trip)
            try context.save()
            state = .idle
            return trip
        } catch is CancellationError {
            state = .idle
            return nil
        } catch {
            state = .failed(error.localizedDescription)
            return nil
        }
    }
}
