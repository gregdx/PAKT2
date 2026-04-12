import SwiftUI

/// City picker sheet shown when the user taps the city pill in EventsFeedView.
/// Lists all RA-supported cities (from /v1/cities), supports text search, and
/// writes the selection back to EventsRemoteStore.selectedCityId.
struct CitySelectionSheet: View {
    @EnvironmentObject var store: EventsRemoteStore
    @Environment(\.dismiss) var dismiss

    @State private var query = ""

    private var filtered: [APIClient.APICity] {
        let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()
        if trimmed.isEmpty { return store.cities }
        return store.cities.filter { city in
            city.name.lowercased().contains(trimmed) ||
            city.countryCode.lowercased().contains(trimmed)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)

                if store.isLoadingCities {
                    ProgressView()
                        .padding(.top, 40)
                    Spacer()
                } else if filtered.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "mappin.slash")
                            .font(.system(size: 32))
                            .foregroundColor(Theme.textFaint)
                        Text("No cities found")
                            .font(.system(size: 15))
                            .foregroundColor(Theme.textMuted)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(filtered) { city in
                                cityRow(city)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                    }
                }
            }
            .navigationTitle("Select a city")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
            .task {
                if store.cities.isEmpty {
                    await store.loadCities()
                }
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundColor(Theme.textFaint)
            TextField("Search a city...", text: $query)
                .font(.system(size: 15))
                .textInputAutocapitalization(.never)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Theme.bgCard)
        )
    }

    private func cityRow(_ city: APIClient.APICity) -> some View {
        let selected = city.id == store.selectedCityId
        return Button {
            store.selectedCityId = city.id
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Text(flagEmoji(for: city.countryCode))
                    .font(.system(size: 24))
                VStack(alignment: .leading, spacing: 2) {
                    Text(city.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Theme.text)
                    Text(city.countryCode)
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textMuted)
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Theme.green)
                        .font(.system(size: 20))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(selected ? Theme.green.opacity(0.08) : Theme.bgCard)
            )
        }
        .buttonStyle(.plain)
    }

    private func flagEmoji(for countryCode: String) -> String {
        let base: UInt32 = 127397
        var result = ""
        for scalar in countryCode.uppercased().unicodeScalars {
            if let flagScalar = UnicodeScalar(base + scalar.value) {
                result.unicodeScalars.append(flagScalar)
            }
        }
        return result.isEmpty ? "🏳️" : result
    }
}
