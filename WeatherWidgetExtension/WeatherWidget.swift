import WidgetKit
import SwiftUI
import WeatherShared

struct WeatherWidget: Widget {
    let kind = "TheDamnWeatherWidget"

    var body: some WidgetConfiguration {
        // AppIntentConfiguration gives each widget its own Edit-Widget picker
        // so the user can pin a specific saved city (or "My Location") per
        // widget instance. This replaces the old StaticConfiguration, which
        // forced every widget to follow whichever city the app was viewing.
        AppIntentConfiguration(
            kind: kind,
            intent: WeatherWidgetIntent.self,
            provider: WeatherWidgetProvider()
        ) { entry in
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
        .description("Weather with attitude. Press and hold to pick a location.")
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
