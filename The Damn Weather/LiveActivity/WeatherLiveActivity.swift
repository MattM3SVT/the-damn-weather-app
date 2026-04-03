import ActivityKit
import WidgetKit
import SwiftUI

struct WeatherLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WeatherActivityAttributes.self) { context in
            // Lock Screen / banner presentation
            ExpandedLiveActivityView(context: context)
                .padding()
                .activityBackgroundTint(.black.opacity(0.7))
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded view
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.locationName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(context.state.conditionLabel)
                            .font(.caption)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Feels \(context.state.feelsLike)°")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 4) {
                            Image(systemName: "wind")
                                .font(.caption2)
                            Text("\(context.state.windSpeed) mph")
                                .font(.caption)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 4) {
                        HStack(spacing: 6) {
                            Image(systemName: context.state.conditionSymbol)
                                .symbolRenderingMode(.multicolor)
                                .font(.title2)
                            Text("\(context.state.temperature)°")
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                        }
                        Text(context.state.phrase)
                            .font(.caption)
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    // Mini hourly strip
                    HStack(spacing: 0) {
                        ForEach(Array(zip(context.state.hourlyHours, context.state.hourlyTemps)), id: \.0) { hour, temp in
                            VStack(spacing: 2) {
                                Text(hour)
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                                Text("\(temp)°")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            } compactLeading: {
                // Compact leading: temperature
                Text("\(context.state.temperature)°")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
            } compactTrailing: {
                // Compact trailing: weather icon
                Image(systemName: context.state.conditionSymbol)
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 14))
            } minimal: {
                // Minimal: just the icon
                Image(systemName: context.state.conditionSymbol)
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 14))
            }
        }
    }
}

struct ExpandedLiveActivityView: View {
    let context: ActivityViewContext<WeatherActivityAttributes>

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(context.attributes.locationName)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Image(systemName: context.state.conditionSymbol)
                        .symbolRenderingMode(.multicolor)
                        .font(.title)

                    Text("\(context.state.temperature)°")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                }

                Text(context.state.phrase)
                    .font(.caption)
                    .lineLimit(2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                Label("\(context.state.feelsLike)°", systemImage: "thermometer.medium")
                    .font(.caption2)
                Label("\(context.state.windSpeed) mph", systemImage: "wind")
                    .font(.caption2)
                if context.state.precipProbability > 0 {
                    Label("\(context.state.precipProbability)%", systemImage: "drop.fill")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                }
            }
            .foregroundStyle(.secondary)
        }
    }
}
