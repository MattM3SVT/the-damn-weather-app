import AppIntents

/// Configuration intent for the weather widget. Invoked by iOS when the user
/// long-presses the widget and taps "Edit Widget". Defaults to `.myLocation`
/// so a freshly-added widget mirrors Apple Weather's behavior.
public struct WeatherWidgetIntent: WidgetConfigurationIntent {
    public static let title: LocalizedStringResource = "Choose Location"
    public static let description = IntentDescription("Pick the city this widget shows.")

    @Parameter(title: "Location", default: LocationEntity.myLocation)
    public var location: LocationEntity

    public init() {}

    public init(location: LocationEntity) {
        self.location = location
    }
}
