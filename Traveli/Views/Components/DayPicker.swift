import SwiftUI

/// Horizontally scrolling day selector (a segmented control doesn't scale to 14 days).
struct DayPicker: View {
    let days: [Day]
    @Binding var selection: Int

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                    let isSelected = index == selection
                    Button {
                        selection = index
                    } label: {
                        VStack(spacing: 2) {
                            Text("Day \(index + 1)").font(.subheadline.weight(.semibold))
                            Text(day.date.formatted(.dateTime.day().month(.abbreviated)))
                                .font(.caption)
                        }
                        .frame(minWidth: 64, minHeight: 44)
                        .padding(.horizontal, 8)
                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                        .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.15),
                                    in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(day.heading(number: index + 1))
                    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }
}
