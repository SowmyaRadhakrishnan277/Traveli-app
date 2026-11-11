import SwiftUI

struct PlaceRow: View {
    let place: Place
    let index: Int
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(index + 1)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Color.accentColor, in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(place.name)
                    .font(.headline)
                Label("\(place.category.title) · \(place.timeSlot.title)", systemImage: place.category.systemImage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                SafetyBadge(place: place)
                Text(place.safetyReason)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if !isLast, place.commuteMinutes > 0 {
                    Label(place.commutePhrase, systemImage: place.commuteMode.systemImage)
                        .font(.footnote.weight(.medium))
                        .padding(.top, 2)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(place.accessibilitySummary(index: index, isLast: isLast))
        .accessibilityHint("Shows safety details")
    }
}
