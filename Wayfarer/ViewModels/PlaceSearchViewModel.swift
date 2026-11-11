import Foundation
import Observation

@MainActor
@Observable
final class PlaceSearchViewModel {
    enum State: Equatable {
        case idle
        case searching
        case results([PlaceSuggestion])
        case empty
        case failed(String)
    }

    var query = ""
    var slot: TimeSlot = .afternoon
    private(set) var state: State = .idle

    private let service: PlacesService
    private let near: GeoPoint?
    private let debounce: Duration

    init(service: PlacesService, near: GeoPoint?, debounce: Duration = .milliseconds(350)) {
        self.service = service
        self.near = near
        self.debounce = debounce
    }

    /// Run from `.task(id: query)`: SwiftUI cancels the previous run on every keystroke.
    func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            state = .idle
            return
        }
        state = .searching
        if debounce > .zero {
            do { try await Task.sleep(for: debounce) } catch { return }
        }
        do {
            let results = try await service.search(query: trimmed, near: near)
            guard !Task.isCancelled else { return }
            state = results.isEmpty ? .empty : .results(results)
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            state = .failed("Search needs an internet connection. Your saved trips stay available offline.")
        }
    }
}
