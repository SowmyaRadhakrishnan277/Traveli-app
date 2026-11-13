import Foundation
import MapKit

struct CommuteEstimate: Sendable, Equatable {
    var minutes: Int
    var mode: CommuteMode
}

protocol RoutingService: Sendable {
    /// Never throws: implementations fall back to an estimate so saved trips
    /// can be edited offline.
    func estimate(from: GeoPoint, to: GeoPoint) async -> CommuteEstimate
}

/// Offline, deterministic estimate based on straight-line distance.
struct HeuristicRoutingService: RoutingService {
    static let walkLimitMetres = 1_200.0
    static let transitLimitMetres = 8_000.0

    /// Straight-line distance understates real routes.
    private static let detourFactor = 1.3

    static func mode(forDistance metres: Double) -> CommuteMode {
        if metres < walkLimitMetres { return .walk }
        return metres < transitLimitMetres ? .transit : .taxi
    }

    func estimate(from: GeoPoint, to: GeoPoint) async -> CommuteEstimate {
        let metres = from.distance(to: to) * Self.detourFactor
        let mode = Self.mode(forDistance: metres)
        let minutes: Double
        switch mode {
        case .walk: minutes = metres / 80            // ~4.8 km/h
        case .transit: minutes = metres / 400 + 8    // ~24 km/h plus waiting
        case .taxi: minutes = metres / 500 + 4       // ~30 km/h plus pickup
        }
        return CommuteEstimate(minutes: max(1, Int(minutes.rounded())), mode: mode)
    }
}

/// Uses MapKit ETAs and falls back to the heuristic on any failure (offline, throttled, no route).
struct MapKitRoutingService: RoutingService {
    var fallback: RoutingService = HeuristicRoutingService()

    func estimate(from: GeoPoint, to: GeoPoint) async -> CommuteEstimate {
        let rough = await fallback.estimate(from: from, to: to)
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: from.coordinate))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: to.coordinate))
        request.transportType = Self.transportType(for: rough.mode)
        do {
            let response = try await MKDirections(request: request).calculateETA()
            let minutes = max(1, Int((response.expectedTravelTime / 60).rounded()))
            return CommuteEstimate(minutes: minutes, mode: rough.mode)
        } catch {
            return rough
        }
    }

    private static func transportType(for mode: CommuteMode) -> MKDirectionsTransportType {
        switch mode {
        case .walk: .walking
        case .transit: .transit
        case .taxi: .automobile
        }
    }
}
