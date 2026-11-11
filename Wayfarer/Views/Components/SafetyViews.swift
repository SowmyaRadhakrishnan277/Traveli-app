import SwiftUI

struct SafetyBadge: View {
    let place: Place

    var body: some View {
        Label {
            Text(place.badgeText)
                .font(.subheadline.weight(.semibold))
        } icon: {
            Image(systemName: place.safetyBand.systemImage)
                .foregroundStyle(place.safetyBand.color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(place.safetyBand.color.opacity(0.15), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Safety: \(place.badgeText)")
    }
}

struct SafetyDisclaimer: View {
    var body: some View {
        Label {
            Text("Safety information is guidance only, not a guarantee of safety. It is based on limited and sometimes biased data. Trust your instincts and check local advice.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } icon: {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

struct OfflineBanner: View {
    var body: some View {
        Label("You're offline. Saved trips are still available.", systemImage: "wifi.slash")
            .font(.footnote.weight(.medium))
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.horizontal)
            .background(.thinMaterial)
            .accessibilityElement(children: .combine)
    }
}
