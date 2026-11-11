import SwiftUI

struct TripFormView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: TripFormViewModel
    private let onCreated: (Trip) -> Void

    init(planner: TripPlanner, onCreated: @escaping (Trip) -> Void) {
        _viewModel = State(initialValue: TripFormViewModel(planner: planner))
        self.onCreated = onCreated
    }

    var body: some View {
        @Bindable var viewModel = viewModel
        NavigationStack {
            Form {
                Section("Where to?") {
                    TextField("Destination, e.g. Lisbon", text: $viewModel.destination)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .frame(minHeight: 44)
                }
                Section("When") {
                    DatePicker("Start", selection: $viewModel.startDate, displayedComponents: .date)
                        .frame(minHeight: 44)
                        .onChange(of: viewModel.startDate) { viewModel.startDateChanged() }
                    DatePicker("End", selection: $viewModel.endDate, in: viewModel.startDate..., displayedComponents: .date)
                        .frame(minHeight: 44)
                }
                Section {
                    Button {
                        Task {
                            if let trip = await viewModel.generate(in: context) {
                                dismiss()
                                onCreated(trip)
                            }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if viewModel.isLoading { ProgressView() }
                            Text(viewModel.isLoading ? "Generating…" : "Generate itinerary")
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!viewModel.canSubmit)
                } footer: {
                    footer
                }
            }
            .navigationTitle("New trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.frame(minWidth: 44, minHeight: 44)
                }
            }
            .interactiveDismissDisabled(viewModel.isLoading)
        }
    }

    @ViewBuilder
    private var footer: some View {
        if case .failed(let message) = viewModel.state {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .accessibilityLabel("Error: \(message)")
        } else if let message = viewModel.validationMessage {
            Text(message).foregroundStyle(.red)
        }
    }
}

#if DEBUG
#Preview {
    TripFormView(planner: AppEnvironment.live.planner) { _ in }
        .modelContainer(PreviewData.container)
}
#endif
