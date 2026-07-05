import ActivityKit
import SwiftUI
import WidgetKit
import WeatherShared

/// Lock screen + Dynamic Island presentation for the rain-countdown
/// Live Activity. The app starts/updates/ends it (RainActivityManager);
/// this file only renders.
struct RainLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RainActivityAttributes.self) { context in
            // Lock screen / banner
            LockScreenRainView(context: context)
                .padding()
                .activityBackgroundTint(.black.opacity(0.7))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.attributes.symbolName)
                        .font(.title2)
                        .foregroundStyle(Color.accentBlue)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    countdown(context)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .frame(width: 64)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.hasStarted
                         ? "\(context.attributes.kind) is here. You were warned."
                         : "\(context.attributes.kind) starting near \(context.attributes.locationName)")
                        .font(.caption)
                        .lineLimit(2)
                }
            } compactLeading: {
                Image(systemName: context.attributes.symbolName)
                    .foregroundStyle(Color.accentBlue)
            } compactTrailing: {
                countdown(context)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .frame(maxWidth: 44)
            } minimal: {
                Image(systemName: context.attributes.symbolName)
                    .foregroundStyle(Color.accentBlue)
            }
        }
    }

    /// Live countdown to onset; "Now" once it has started. `timerInterval`
    /// keeps ticking without any process running.
    @ViewBuilder
    private func countdown(_ context: ActivityViewContext<RainActivityAttributes>) -> some View {
        if context.state.hasStarted {
            Text("Now")
        } else {
            Text(timerInterval: Date()...max(context.state.startsAt, Date().addingTimeInterval(1)),
                 countsDown: true)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct LockScreenRainView: View {
    let context: ActivityViewContext<RainActivityAttributes>

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: context.attributes.symbolName)
                .font(.system(size: 30))
                .foregroundStyle(Color.accentBlue)

            VStack(alignment: .leading, spacing: 2) {
                Text(context.state.hasStarted
                     ? "\(context.attributes.kind) is here."
                     : "\(context.attributes.kind) starting soon")
                    .font(.headline)
                Text(context.attributes.locationName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if context.state.hasStarted {
                Text("Now")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
            } else {
                Text(timerInterval: Date()...max(context.state.startsAt, Date().addingTimeInterval(1)),
                     countsDown: true)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .frame(maxWidth: 90)
                    .multilineTextAlignment(.trailing)
            }
        }
        .foregroundStyle(.white)
    }
}

extension RainActivityAttributes {
    var symbolName: String {
        kind == "Snow" ? "snowflake" : "umbrella.fill"
    }
}
