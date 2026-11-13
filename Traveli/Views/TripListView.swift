import SwiftData
import SwiftUI

struct TripListView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.appEnvironment) private var environment
    @Environment(NetworkMonitor.self) private var network
    @Query(sort: \Trip.startDate, order: .reverse) private var trips: [Trip]

    @State private var path: [Trip] = []
    @State private var showingForm = false

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if trips.isEmpty {
                    VStack(spacing: 16) {
                        TravelerCharacter()
                            .frame(height: 210)
                        Text("Where to next?")
                            .font(.title2.bold())
                        Text("Tell me where you're going and I'll plan a day-by-day trip with safety guidance.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        Button("Plan a trip") { showingForm = true }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityElement(children: .contain)
                } else {
                    List {
                        ForEach(trips) { trip in
                            NavigationLink(value: trip) { TripRow(trip: trip) }
                        }
                        .onDelete(perform: delete)
                    }
                }
            }
            .navigationTitle("Traveli")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingForm = true } label: { Label("New trip", systemImage: "plus") }
                        .frame(minWidth: 44, minHeight: 44)
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if !network.isOnline { OfflineBanner() }
            }
            .navigationDestination(for: Trip.self) { trip in
                ItineraryView(trip: trip, environment: environment)
            }
            .sheet(isPresented: $showingForm) {
                TripFormView(planner: environment.planner) { trip in path.append(trip) }
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        offsets.map { trips[$0] }.forEach(context.delete)
        try? context.save()
    }
}

private struct TripRow: View {
    let trip: Trip

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(trip.destination).font(.headline)
            Text("\(trip.startDate.formatted(date: .abbreviated, time: .omitted)) – \(trip.endDate.formatted(date: .abbreviated, time: .omitted))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("\(trip.days.count) days · \(trip.placeCount) places")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(minHeight: 44, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview("With trip") {
    _ = PreviewData.sampleTrip()
    return TripListView()
        .environment(NetworkMonitor())
        .modelContainer(PreviewData.container)
}

#Preview("Empty") {
    TripListView()
        .environment(NetworkMonitor())
        .modelContainer(for: [Trip.self, Day.self, Place.self], inMemory: true)
}
#endif
