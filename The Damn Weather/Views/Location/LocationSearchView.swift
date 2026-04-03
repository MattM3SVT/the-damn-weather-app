import SwiftUI
import CoreLocation

struct LocationSearchView: View {
    @Bindable var viewModel: LocationSearchViewModel
    let onSelect: ((name: String, state: String, country: String, location: CLLocation)) -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search field
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search city or zip code...", text: $viewModel.searchText)
                        .focused($isSearchFocused)
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                        .onChange(of: viewModel.searchText) { _, newValue in
                            viewModel.updateSearch(newValue)
                        }
                    if !viewModel.searchText.isEmpty {
                        Button {
                            viewModel.clear()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding()
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cornerRadius))
                .padding()

                // Results list
                List {
                    // Current location option
                    Button {
                        dismiss()
                        // Will be handled by the parent using device location
                    } label: {
                        Label("Current Location", systemImage: "location.fill")
                    }

                    ForEach(viewModel.results) { result in
                        Button {
                            Task {
                                if let selected = await viewModel.selectResult(result) {
                                    onSelect(selected)
                                }
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.title)
                                    .font(.body)
                                if !result.subtitle.isEmpty {
                                    Text(result.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("Search Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            isSearchFocused = true
        }
    }
}
