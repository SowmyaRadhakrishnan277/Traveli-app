import Foundation
import MapKit

struct PlaceSuggestion: Identifiable, Hashable, Sendable {
    var name: String
    var subtitle: String
    var category: PlaceCategory
    var location: GeoPoint

    var id: String { "\(name)|\(location.latitude)|\(location.longitude)" }
}

protocol PlacesService: Sendable {
    /// Finds places matching `query`, biased toward `near` when provided.
    func search(query: String, near: GeoPoint?) async throws -> [PlaceSuggestion]
}

/// MapKit local search. No API key needed.
struct MapKitPlacesService: PlacesService {
    func search(query: String, near: GeoPoint?) async throws -> [PlaceSuggestion] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        if let near {
            request.region = MKCoordinateRegion(
                center: near.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.2, longitudeDelta: 0.2)
            )
        }
        let response = try await MKLocalSearch(request: request).start()
        return response.mapItems.prefix(15).compactMap { item in
            guard let name = item.name else { return nil }
            let coordinate = item.placemark.coordinate
            return PlaceSuggestion(
                name: name,
                subtitle: item.placemark.title ?? "",
                category: Self.category(for: item.pointOfInterestCategory),
                location: GeoPoint(latitude: coordinate.latitude, longitude: coordinate.longitude)
            )
        }
    }

    static func category(for poi: MKPointOfInterestCategory?) -> PlaceCategory {
        guard let poi else { return .other }
        switch poi {
        case .museum: return .museum
        case .park, .nationalPark: return .park
        case .restaurant: return .restaurant
        case .cafe, .bakery: return .cafe
        case .foodMarket: return .market
        case .nightlife, .brewery, .winery: return .nightlife
        case .beach: return .beach
        case .publicTransport, .airport: return .transit
        case .library, .theater, .stadium: return .landmark
        default: return .other
        }
    }
}
