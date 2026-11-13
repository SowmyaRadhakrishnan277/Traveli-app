import MapKit
import SwiftData
import SwiftUI

struct ItineraryView: View {
    @State private var viewModel: ItineraryViewModel
    @State private var position: MapCameraPosition = .automatic
    @State private var showingAddPlace = false
    @State private var detailPlace: Place?
    @Environment(NetworkMonitor.self) private var network
    private let placesService: PlacesService

    init(trip: Trip, environment: AppEnvironment) {
        _viewModel = State(initialValue: ItineraryViewModel(trip: trip, planner: environment.planner))
        placesService = environment.places
    }

    var body: some View {
        @Bindable var viewModel = viewModel
        VStack(spacing: 0) {
            if !network.isOnline { OfflineBanner() }
            if viewModel.days.isEmpty {
                ContentUnavailableView("No days in this trip", systemImage: "calendar.badge.exclamationmark")
            } else {
                DayPicker(days: viewModel.days, selection: $viewModel.selectedDayIndex)
                mapView
                placeList
            }
        }
        .navigationTitle(viewModel.trip.destination)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if viewModel.isWorking { ProgressView().accessibilityLabel("Updating travel times") }
                Button { showingAddPlace = true } label: { Label("Add place", systemImage: "plus") }
                    .frame(minWidth: 44, minHeight: 44)
                EditButton().frame(minWidth: 44, minHeight: 44)
            }
        }
        .sheet(isPresented: $showingAddPlace) {
            AddPlaceView(service: placesService, near: viewModel.places.first?.location) { suggestion, slot in
                Task { await viewModel.add(suggestion, slot: slot) }
            }
        }
        .sheet(item: $detailPlace) { PlaceDetailView(place: $0) }
        .alert("Something went wrong", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .onAppear { refit() }
        .onChange(of: viewModel.mapFitToken) { refit() }
    }

    // MARK: - Subviews

    private var mapView: some View {
        let places = viewModel.places
        return Map(position: $position) {
            ForEach(Array(places.enumerated()), id: \.element.persistentModelID) { index, place in
                Marker("\(index + 1). \(place.name)", systemImage: place.category.systemImage, coordinate: place.location.coordinate)
                    .tint(place.safetyBand.color)
            }
            if places.count > 1 {
                MapPolyline(coordinates: places.map { $0.location.coordinate })
                    .stroke(.tint, style: StrokeStyle(lineWidth: 3, dash: [6, 4]))
            }
        }
        .frame(height: 220)
        .overlay {
            if places.isEmpty { Text("Add a place to see it on the map").padding(8).background(.thinMaterial, in: Capsule()) }
        }
        .accessibilityLabel("Map showing \(places.count) stops for the selected day")
    }

    private var placeList: some View {
        let places = viewModel.places
        let dayNumber = viewModel.selectedDayIndex + 1
        return List {
            Section {
                if places.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Nothing planned yet").font(.headline)
                        Button("Add a place") { showingAddPlace = true }
                            .buttonStyle(.borderedProminent)
                            .frame(minHeight: 44)
                    }
                    .padding(.vertical, 4)
                }
                ForEach(Array(places.enumerated()), id: \.element.persistentModelID) { index, place in
                    Button { detailPlace = place } label: {
                        PlaceRow(place: place, index: index, isLast: index == places.count - 1)
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { viewModel.delete(at: $0) }
                .onMove { viewModel.move(from: $0, to: $1) }
            } header: {
                Text(viewModel.selectedDay?.heading(number: dayNumber) ?? "")
            }
            Section { SafetyDisclaimer() }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Helpers

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )
    }

    private func refit() {
        if let region = viewModel.mapRegion {
            withAnimation { position = .region(region) }
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        ItineraryView(trip: PreviewData.sampleTrip(), environment: .live)
    }
    .environment(NetworkMonitor())
    .modelContainer(PreviewData.container)
}
#endif
