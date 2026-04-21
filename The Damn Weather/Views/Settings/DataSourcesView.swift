import SwiftUI

/// Discloses the three weather data sources the app uses.
/// Reached from Settings → About → "About Our Data".
struct DataSourcesView: View {
    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: DesignTokens.spaceSM) {
                    Text("Forecasts, alerts, and all the numbers — temperature, wind, UV, humidity, minute-by-minute precipitation, hourly and 10-day outlooks. Same data Apple's own Weather app uses.")
                        .font(.system(size: DesignTokens.bodySize))
                    if let url = URL(string: "https://weatherkit.apple.com/legal-attribution.html") {
                        Link(destination: url) {
                            Label("Apple's data sources", systemImage: "arrow.up.right.square")
                                .font(.system(size: DesignTokens.smallSize, weight: .medium))
                        }
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("WeatherKit (Apple)")
            }

            Section {
                VStack(alignment: .leading, spacing: DesignTokens.spaceSM) {
                    Text("For US locations, we check the nearest airport's actual cloud observation against what WeatherKit is saying. When forecasts and real observations disagree, the observation wins. Run by NOAA.")
                        .font(.system(size: DesignTokens.bodySize))
                    if let url = URL(string: "https://www.weather.gov/documentation/services-web-api") {
                        Link(destination: url) {
                            Label("api.weather.gov", systemImage: "arrow.up.right.square")
                                .font(.system(size: DesignTokens.smallSize, weight: .medium))
                        }
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("National Weather Service")
            }

            Section {
                VStack(alignment: .leading, spacing: DesignTokens.spaceSM) {
                    Text("Independent second opinion on current sky conditions from the same airport sensors pilots use. When both NWS and METAR disagree with WeatherKit, we trust the ground truth.")
                        .font(.system(size: DesignTokens.bodySize))
                    if let url = URL(string: "https://aviationweather.gov/data/api/") {
                        Link(destination: url) {
                            Label("aviationweather.gov", systemImage: "arrow.up.right.square")
                                .font(.system(size: DesignTokens.smallSize, weight: .medium))
                        }
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("METAR (Aviation Weather Center)")
            } footer: {
                Text("We only cross-check the current sky condition. Forecasts, alerts, and every other piece of data come from WeatherKit.")
            }
        }
        .navigationTitle("About Our Data")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        DataSourcesView()
    }
}
