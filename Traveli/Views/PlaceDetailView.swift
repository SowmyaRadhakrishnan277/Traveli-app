import SwiftUI

struct PlaceDetailView: View {
    let place: Place
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Safety guidance") {
                    HStack {
                        Text("Rating")
                        Spacer()
                        SafetyBadge(place: place)
                    }
                    .frame(minHeight: 44)
                    LabeledContent("Confidence", value: place.safetyConfidence.title)
                        .frame(minHeight: 44)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Why").font(.subheadline.weight(.semibold))
                        Text(place.safetyReason)
                    }
                    .accessibilityElement(children: .combine)
                }

                Section("Day vs night") {
                    noteRow(title: "Daytime", systemImage: "sun.max", text: place.safetyDayNote)
                    noteRow(title: "After dark", systemImage: "moon.stars", text: place.safetyNightNote)
                }

                Section("Sources") {
                    if place.sources.isEmpty {
                        Text("No sources available").foregroundStyle(.secondary)
                    } else {
                        ForEach(place.sources, id: \.self) { Text($0) }
                    }
                }

                Section { SafetyDisclaimer() }
            }
            .navigationTitle(place.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.frame(minWidth: 44, minHeight: 44)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func noteRow(title: String, systemImage: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: systemImage).font(.subheadline.weight(.semibold))
            Text(text.isEmpty ? "No information available." : text)
        }
        .frame(minHeight: 44, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
