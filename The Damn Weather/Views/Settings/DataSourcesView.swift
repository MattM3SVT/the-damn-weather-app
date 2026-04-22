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
                Text("We only cross-check the current sky condition against NWS and METAR. Forecasts, alerts, and every other piece of data come from WeatherKit.")
            }

            Section {
                VStack(alignment: .leading, spacing: DesignTokens.spaceSM) {
                    Text("US air quality index and pollutant readings from the U.S. EPA AirNow network of state, local, tribal, and federal monitoring stations. Covers the contiguous US, Alaska, Hawaii, and Puerto Rico. When you're outside AirNow's coverage, the Air Quality card is hidden.")
                        .font(.system(size: DesignTokens.bodySize))
                    if let url = URL(string: "https://www.airnow.gov/") {
                        Link(destination: url) {
                            Label("airnow.gov", systemImage: "arrow.up.right.square")
                                .font(.system(size: DesignTokens.smallSize, weight: .medium))
                        }
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("AirNow (U.S. EPA)")
            } footer: {
                Text("Air quality is supplemental and US-only. When no nearby monitor is reporting, we hide the card rather than guess.")
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
