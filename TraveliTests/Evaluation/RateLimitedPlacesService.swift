import Foundation
import MapKit
@testable import Traveli

/// Spaces out map lookups and retries when the service throttles. Needed because MapKit allows only
/// about 50 searches a minute: without this, a long experiment silently turns "throttled" into
/// "the model invented a place" and corrupts the data.
///
/// Also caches lookups made without a location (the destination-centre lookup), which repeat once
/// per prompt variant for the same city. Verification lookups are deliberately not cached.
actor RateLimitedPlacesService: PlacesService {
    private let base: PlacesService
    private let minInterval: Duration
    private let retryDelay: Duration
    private let maxRetries: Int
    private var nextSlot = ContinuousClock.now
    private var centreCache: [String: [PlaceSuggestion]] = [:]

    private(set) var throttleRetries = 0

    init(base: PlacesService, minInterval: Duration = .milliseconds(1500),
         retryDelay: Duration = .seconds(20), maxRetries: Int = 4) {
        self.base = base
        self.minInterval = minInterval
        self.retryDelay = retryDelay
        self.maxRetries = maxRetries
    }

    func search(query: String, near: GeoPoint?) async throws -> [PlaceSuggestion] {
        if near == nil, let cached = centreCache[query] { return cached }

        var attempt = 0
        while true {
            try await waitForSlot()
            do {
                let results = try await base.search(query: query, near: near)
                if near == nil { centreCache[query] = results }
                return results
            } catch {
                guard Self.isThrottle(error), attempt < maxRetries else { throw error }
                attempt += 1
                throttleRetries += 1
                try await Task.sleep(for: retryDelay)
            }
        }
    }

    private func waitForSlot() async throws {
        let now = ContinuousClock.now
        let start = max(now, nextSlot)
        nextSlot = start + minInterval
        if start > now { try await Task.sleep(until: start, clock: .continuous) }
    }

    static func isThrottle(_ error: Error) -> Bool {
        let ns = error as NSError
        return ns.domain == MKErrorDomain && ns.code == Int(MKError.Code.loadingThrottled.rawValue)
    }
}
