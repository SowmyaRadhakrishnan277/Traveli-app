import Foundation

/// Hand-written demo content for a few cities, plus a generic fallback.
struct CityTemplate: Sendable {
    struct Stop: Sendable {
        let name: String
        let category: PlaceCategory
        let latitude: Double
        let longitude: Double
    }

    let morning: [Stop]
    let afternoon: [Stop]
    let evening: [Stop]

    /// Rotates through each slot's list so consecutive days differ.
    func proposals(forDay index: Int) -> [PlaceProposal] {
        func pick(_ stops: [Stop], _ slot: TimeSlot) -> PlaceProposal? {
            guard !stops.isEmpty else { return nil }
            let stop = stops[index % stops.count]
            return PlaceProposal(
                name: stop.name,
                category: stop.category,
                location: GeoPoint(latitude: stop.latitude, longitude: stop.longitude),
                timeSlot: slot
            )
        }
        return [pick(morning, .morning), pick(afternoon, .afternoon), pick(evening, .evening)].compactMap { $0 }
    }
}

enum MockCityCatalog {
    static func template(for destination: String) -> CityTemplate? {
        let normalized = normalize(destination)
        return cities.first { normalized == $0.key || normalized.hasPrefix($0.key + " ") || normalized.hasPrefix($0.key + ",") }?.value
    }

    static func normalize(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
    }

    /// Placeholder stops around a city centre, for destinations without hand-written content.
    static func generic(around centre: GeoPoint) -> CityTemplate {
        func stop(_ name: String, _ category: PlaceCategory, _ dLat: Double, _ dLon: Double) -> CityTemplate.Stop {
            .init(name: name, category: category, latitude: centre.latitude + dLat, longitude: centre.longitude + dLon)
        }
        return CityTemplate(
            morning: [
                stop("Old Town Walk", .landmark, 0.004, -0.003),
                stop("City Museum", .museum, -0.005, 0.004),
                stop("Central Park", .park, 0.008, 0.006),
                stop("Neighbourhood Bakery Café", .cafe, -0.002, -0.006),
            ],
            afternoon: [
                stop("Central Market", .market, 0.001, 0.002),
                stop("Cathedral Quarter", .landmark, 0.006, -0.007),
                stop("Riverside Promenade", .park, -0.007, 0.001),
                stop("Art Gallery", .museum, 0.003, 0.009),
            ],
            evening: [
                stop("Sunset Viewpoint", .viewpoint, 0.009, -0.002),
                stop("Local Food Street", .restaurant, -0.003, 0.005),
                stop("Old Town Bar District", .nightlife, 0.002, -0.004),
                stop("Rooftop Restaurant", .restaurant, -0.004, -0.001),
            ]
        )
    }

    private static func s(_ n: String, _ c: PlaceCategory, _ lat: Double, _ lon: Double) -> CityTemplate.Stop {
        .init(name: n, category: c, latitude: lat, longitude: lon)
    }

    private static let cities: [String: CityTemplate] = [
        "lisbon": CityTemplate(
            morning: [
                s("Jardim da Estrela", .park, 38.7133, -9.1592),
                s("Museu Nacional do Azulejo", .museum, 38.7253, -9.1131),
                s("Pastéis de Belém", .cafe, 38.6975, -9.2032),
                s("Jerónimos Monastery", .landmark, 38.6979, -9.2068),
            ],
            afternoon: [
                s("Belém Tower", .landmark, 38.6916, -9.2160),
                s("LX Factory", .market, 38.7033, -9.1787),
                s("Praça do Comércio", .landmark, 38.7075, -9.1364),
                s("Lisbon Cathedral", .landmark, 38.7098, -9.1330),
            ],
            evening: [
                s("Miradouro da Senhora do Monte", .viewpoint, 38.7196, -9.1329),
                s("Time Out Market", .restaurant, 38.7064, -9.1459),
                s("Bairro Alto", .nightlife, 38.7129, -9.1458),
                s("Pink Street", .nightlife, 38.7062, -9.1450),
            ]
        ),
        "paris": CityTemplate(
            morning: [
                s("Jardin du Luxembourg", .park, 48.8462, 2.3372),
                s("Louvre Museum", .museum, 48.8606, 2.3376),
                s("Café de Flore", .cafe, 48.8541, 2.3333),
                s("Musée d'Orsay", .museum, 48.8600, 2.3266),
            ],
            afternoon: [
                s("Eiffel Tower", .landmark, 48.8584, 2.2945),
                s("Marché des Enfants Rouges", .market, 48.8630, 2.3627),
                s("Pont Alexandre III", .landmark, 48.8639, 2.3135),
                s("Canal Saint-Martin", .park, 48.8720, 2.3660),
            ],
            evening: [
                s("Sacré-Cœur", .viewpoint, 48.8867, 2.3431),
                s("Le Marais", .restaurant, 48.8575, 2.3622),
                s("Oberkampf", .nightlife, 48.8650, 2.3790),
                s("Seine Riverbank", .viewpoint, 48.8566, 2.3400),
            ]
        ),
        "tokyo": CityTemplate(
            morning: [
                s("Meiji Shrine", .landmark, 35.6764, 139.6993),
                s("Ueno Park", .park, 35.7156, 139.7745),
                s("Tsukiji Outer Market", .market, 35.6655, 139.7707),
                s("Nezu Museum", .museum, 35.6620, 139.7180),
            ],
            afternoon: [
                s("Senso-ji", .landmark, 35.7148, 139.7967),
                s("Shinjuku Gyoen", .park, 35.6852, 139.7100),
                s("teamLab Planets", .museum, 35.6491, 139.7898),
                s("Yanaka Ginza", .market, 35.7276, 139.7680),
            ],
            evening: [
                s("Shibuya Sky", .viewpoint, 35.6585, 139.7022),
                s("Omoide Yokocho", .restaurant, 35.6931, 139.6998),
                s("Golden Gai", .nightlife, 35.6940, 139.7036),
                s("Tokyo Station Ramen Street", .restaurant, 35.6812, 139.7671),
            ]
        ),
    ]
}
