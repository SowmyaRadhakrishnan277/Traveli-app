import SwiftUI

/// Full-screen "planning" state: the walking mascot while the itinerary is built.
struct GeneratingOverlay: View {
    var body: some View {
        VStack(spacing: 12) {
            TravelerCharacter()
                .frame(height: 190)
            Text("Planning your trip…")
                .font(.title3.weight(.semibold))
            Text("Finding great places and checking them on the map.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Planning your trip")
        .accessibilityAddTraits(.updatesFrequently)
    }
}

/// Says whether the itinerary is AI-made or a sample, so nothing is passed off as something it isn't.
struct GenerationBanner: View {
    let trip: Trip

    var body: some View {
        if trip.isAIGenerated {
            Label("AI-generated on your device. Places were checked on Apple Maps; please review before you go.",
                  systemImage: "sparkles")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .combine)
        } else {
            Label(trip.generationNote.isEmpty ? "Sample itinerary." : trip.generationNote,
                  systemImage: "info.circle")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .combine)
        }
    }
}
