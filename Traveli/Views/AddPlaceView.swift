import SwiftUI

struct AddPlaceView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: PlaceSearchViewModel
    private let onAdd: (PlaceSuggestion, TimeSlot) -> Void

    init(service: PlacesService, near: GeoPoint?, onAdd: @escaping (PlaceSuggestion, TimeSlot) -> Void) {
        _viewModel = State(initialValue: PlaceSearchViewModel(service: service, near: near))
        self.onAdd = onAdd
    }

    var body: some View {
        @Bindable var viewModel = viewModel
        NavigationStack {
            List {
                Section("Time of day") {
                    Picker("Time of day", selection: $viewModel.slot) {
                        ForEach(TimeSlot.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                resultsSection
            }
            .navigationTitle("Add a place")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $viewModel.query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search places")
            .task(id: viewModel.query) { await viewModel.search() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.frame(minWidth: 44, minHeight: 44)
                }
            }
        }
    }

    @ViewBuilder
    private var resultsSection: some View {
        switch viewModel.state {
        case .idle:
            statusRow("Search for a café, museum, restaurant or landmark.", systemImage: "magnifyingglass")
        case .searching:
            HStack(spacing: 12) {
                ProgressView()
                Text("Searching…")
            }
            .frame(minHeight: 44)
            .accessibilityElement(children: .combine)
        case .empty:
            statusRow("No places found. Try a different search.", systemImage: "mappin.slash")
        case .failed(let message):
            statusRow(message, systemImage: "wifi.exclamationmark")
        case .results(let suggestions):
            Section("Results") {
                ForEach(suggestions) { suggestion in
                    Button {
                        onAdd(suggestion, viewModel.slot)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(suggestion.name).font(.headline)
                            if !suggestion.subtitle.isEmpty {
                                Text(suggestion.subtitle).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Adds to this day")
                }
            }
        }
    }

    private func statusRow(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .foregroundStyle(.secondary)
            .frame(minHeight: 44)
    }
}
