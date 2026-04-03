import WidgetKit
import SwiftUI
import WeatherShared

struct WeatherWidget: Widget {
    let kind = "TheDamnWeatherWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WeatherWidgetProvider()) { entry in
            WeatherWidgetEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    WeatherGradients.gradient(
                        for: entry.conditionTag,
                        isDay: entry.isDay,
                        colorScheme: .dark  // Widgets look best with dark backgrounds
                    )
                }
        }
        .configurationDisplayName("The Damn Weather")
        .description("Weather with attitude. Tap for a new phrase.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct WeatherWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: WeatherWidgetEntry

    var body: some View {
        switch family {
        case .systemSmall:
            SmallWidgetView(entry: entry)
        case .systemMedium:
            MediumWidgetView(entry: entry)
        case .systemLarge:
            LargeWidgetView(entry: entry)
        default:
            SmallWidgetView(entry: entry)
        }
    }
}
