import Foundation

extension Date {
    /// Format as hour label (e.g., "3 PM").
    /// "Now" detection is handled by callers (HourlyForecastView, widget) — not here.
    public func hourLabel(timezone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = timezone
        formatter.dateFormat = "h a"
        return formatter.string(from: self)
    }

    /// Format as time string (e.g., "7:30 AM")
    public func timeString(timezone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = timezone
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: self)
    }

    /// Format as minute-past-the-hour (e.g., ":15"), for minute-granularity axis labels.
    public func minuteLabel(timezone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = timezone
        formatter.dateFormat = ":mm"
        return formatter.string(from: self)
    }

    /// Format as day label (e.g., "Mon", "Today")
    public func dayLabel(index: Int = -1, timezone: TimeZone = .current) -> String {
        var calendar = Calendar.current
        calendar.timeZone = timezone
        if index == 0 || calendar.isDateInToday(self) {
            return "Today"
        }
        let formatter = DateFormatter()
        formatter.timeZone = timezone
        formatter.dateFormat = "EEE"
        return formatter.string(from: self)
    }

    /// Format as short date (e.g., "Apr 1")
    public func shortDate(timezone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = timezone
        formatter.dateFormat = "MMM d"
        return formatter.string(from: self)
    }

    /// Format as current time (e.g., "3:45 PM")
    public static func currentTimeString(timezone: TimeZone = .current) -> String {
        Date().timeString(timezone: timezone)
    }

    /// Hour of day (0–23) in the given timezone. Used to gate time-bucketed
    /// phrases to the *location's* wall clock, not the device's.
    public func localHour(timezone: TimeZone = .current) -> Int {
        var calendar = Calendar.current
        calendar.timeZone = timezone
        return calendar.component(.hour, from: self)
    }
}
