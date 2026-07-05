import SwiftUI
import WatchKit
import WeatherShared

/// Four vertically paged screens, one idea each. Design system:
///  - Consistent margins; trailing space reserved for the page-indicator dots.
///  - Zones grounded in ultraThinMaterial containers, not floating elements.
///  - SF Rounded everywhere; explicit icon tints (multicolor falls back to
///    monochrome for symbols without color variants, which looked broken).
///  - accentRed strictly as an accent: quote mark, location arrow, glyphs.
///  - The gradient temperature bars from the iPhone large widget reappear on
///    the forecast page — the most recognizable branded visual the app has.
struct WatchWeatherView: View {
    @State private var provider = WatchWeatherProvider()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if let state = provider.state {
                TabView {
                    PhrasePage(state: state) {
                        Task { await provider.newPhrase() }
                    }
                    .weatherPage(state)

                    NowPage(state: state)
                        .weatherPage(state)

                    DetailsPage(state: state) {
                        Task { await provider.refresh() }
                    }
                    .weatherPage(state)

                    ForecastPage(state: state)
                        .weatherPage(state)
                }
                .tabViewStyle(.verticalPage)
            } else if let message = provider.errorMessage {
                VStack(spacing: 8) {
                    Text("Well, damn.").font(.system(.headline, design: .rounded))
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Retry") { Task { await provider.refresh() } }
                        .tint(.accentRed)
                }
            } else {
                ProgressView("Loading the attitude...")
            }
        }
        .task { await provider.refreshIfStale() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await provider.refreshIfStale() }
            }
        }
    }
}

private extension View {
    /// Shared page treatment: condition gradient + margins. Extra trailing
    /// padding keeps content clear of the vertical page-indicator dots.
    func weatherPage(_ state: WatchWeatherProvider.State) -> some View {
        self
            .padding(.trailing, 8)
            .foregroundStyle(.white)
            .containerBackground(for: .tabView) {
                WeatherGradients.gradient(
                    for: state.conditionTag,
                    isDay: state.isDay,
                    colorScheme: .dark
                )
            }
    }
}

// MARK: - Page 1: THE PHRASE

private struct PhrasePage: View {
    let state: WatchWeatherProvider.State
    let onPhraseTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 3) {
                Image(systemName: "location.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.accentRed)
                Text(state.locationName)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            // The phrase, unadorned. Tried a pull-quote mark twice at this
            // scale; it read as stray punctuation. Type carries the page.
            Text(state.phrase)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .lineLimit(4)
                .minimumScaleFactor(0.75)
                .lineSpacing(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentTransition(.opacity)
                .contentShape(Rectangle())
                .onTapGesture {
                    WKInterfaceDevice.current().play(.click)
                    onPhraseTap()
                }

            Spacer(minLength: 4)

            // Grounded footer bar instead of floating fragments.
            HStack(spacing: 5) {
                Image(systemName: state.conditionTag.sfSymbol(isDay: state.isDay))
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 14))
                Text("\(state.temperature)°")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                Spacer()
                Text("H \(state.high)°")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                Text("L \(state.low)°")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
        }
    }
}

// MARK: - Page 2: now

private struct NowPage: View {
    let state: WatchWeatherProvider.State

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // One aligned cluster: temp is the hero, condition + H/L stack
            // beside it on a shared leading edge.
            HStack(alignment: .top) {
                Text("\(state.temperature)°")
                    .font(.system(size: 54, weight: .black, design: .rounded))
                Spacer()
                Image(systemName: state.conditionTag.sfSymbol(isDay: state.isDay))
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 26))
                    .padding(.top, 6)
            }

            HStack(spacing: 8) {
                Text(state.conditionLabel)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer()
                Text("H \(state.high)°")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Text("L \(state.low)°")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
            }

            Spacer(minLength: 6)

            HStack(spacing: 0) {
                ForEach(state.hourly) { h in
                    VStack(spacing: 3) {
                        Text(h.hour)
                            .font(.system(size: 10, design: .rounded))
                            .foregroundStyle(.white.opacity(0.6))
                        Image(systemName: h.tag.sfSymbol(isDay: h.isDay))
                            .symbolRenderingMode(.multicolor)
                            .font(.system(size: 13))
                        Text("\(h.temp)°")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

// MARK: - Page 3: details + refresh

private struct DetailsPage: View {
    let state: WatchWeatherProvider.State
    let onRefresh: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                GridRow {
                    detail("thermometer.medium", .accentRed, "Feels", "\(state.feelsLike)°")
                    detail("wind", .cyan, "Wind", "\(state.windMph) mph")
                }
                GridRow {
                    detail("humidity.fill", Color(red: 0.4, green: 0.7, blue: 1.0), "Humidity", "\(state.humidity)%")
                    detail("sun.max.fill", .yellow, "UV", "\(state.uvIndex)")
                }
            }

            // Quiet by design: timestamps are metadata, not a call to action.
            Button {
                WKInterfaceDevice.current().play(.click)
                onRefresh()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.accentRed)
                    (Text("Updated ") + Text(state.fetchedAt, style: .relative) + Text(" ago"))
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.ultraThinMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private func detail(_ symbol: String, _ tint: Color, _ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Page 4: 5-day forecast with range bars

private struct ForecastPage: View {
    let state: WatchWeatherProvider.State

    var body: some View {
        let minTemp = state.daily.map(\.low).min() ?? 0
        let maxTemp = state.daily.map(\.high).max() ?? 100
        let range = max(Double(maxTemp - minTemp), 1)

        VStack(spacing: 5) {
            ForEach(state.daily) { day in
                HStack(spacing: 6) {
                    Text(day.day)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .frame(width: 38, alignment: .leading)
                    Image(systemName: day.tag.sfSymbol(isDay: true))
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 12))
                        .frame(width: 16)
                    Text("\(day.low)°")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 22, alignment: .trailing)

                    // The brand bar: same blue→red range gradient as the
                    // iPhone large widget's daily rows.
                    GeometryReader { geo in
                        let leftPct = Double(day.low - minTemp) / range
                        let rightPct = Double(maxTemp - day.high) / range
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.15)).frame(height: 3)
                            Capsule()
                                .fill(LinearGradient(
                                    colors: [.accentBlue, .accentRed],
                                    startPoint: .leading, endPoint: .trailing
                                ))
                                .frame(width: max(geo.size.width * (1 - leftPct - rightPct), 3), height: 3)
                                .offset(x: geo.size.width * leftPct)
                        }
                        .frame(maxHeight: .infinity, alignment: .center)
                    }

                    Text("\(day.high)°")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .frame(width: 24, alignment: .trailing)
                }
                .frame(height: 20)
            }

            Spacer(minLength: 2)

            Text("thedamnweather")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .tracking(1)
                .foregroundStyle(.white.opacity(0.35))
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}
