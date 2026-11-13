import Foundation

/// A stop suggested by an AI model, before it has been checked against a real map.
struct StopCandidate: Sendable, Equatable {
    var name: String
    var category: String
    var timeSlot: String
}

/// Language models invent places. Every AI stop is looked up on the map and only
/// kept when it resolves to a real place near the destination; coordinates and names
/// always come from the map result, never from the model.
struct StopVerifier: Sendable {
    let places: PlacesService
    /// Reject matches farther than this from the destination centre (wrong city, same name).
    var maxDistanceMetres: Double = 30_000

    func verify(
        _ candidates: [StopCandidate],
        destination: String,
        centre: GeoPoint,
        excluding used: Set<String> = []
    ) async -> [PlaceProposal] {
        var seen = used
        var verified: [PlaceProposal] = []
        for (index, candidate) in candidates.enumerated() {
            let name = candidate.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            let hits = (try? await places.search(query: "\(name) \(destination)", near: centre)) ?? []
            guard let hit = hits.first(where: { $0.location.distance(to: centre) <= maxDistanceMetres }) else { continue }

            let key = Self.key(hit.name)
            guard seen.insert(key).inserted else { continue }

            let fallbackSlot = TimeSlot.allCases[min(index, TimeSlot.allCases.count - 1)]
            verified.append(PlaceProposal(
                name: hit.name,
                category: hit.category != .other ? hit.category : (PlaceCategory(rawValue: candidate.category.lowercased()) ?? .other),
                location: hit.location,
                timeSlot: TimeSlot(rawValue: candidate.timeSlot.lowercased()) ?? fallbackSlot
            ))
        }
        return verified.sorted { $0.timeSlot < $1.timeSlot }
    }

    static func key(_ name: String) -> String {
        name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
