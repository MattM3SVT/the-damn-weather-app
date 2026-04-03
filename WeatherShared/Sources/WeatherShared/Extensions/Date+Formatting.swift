import Foundation

extension Date {
    /// Format as hour label (e.g., "3 PM", "Now")
    public func hourLabel(timezone: TimeZone = .current, relativeTo now: Date = Date()) -> String {
        let cal = Calendar.current
        if cal.isDate(self, equalTo: now, toGranularity: .hour) &&
           cal.isDate(self, inSameDayAs: now) {
            return "Now"
        }

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

    /// Format as day label (e.g., "Mon", "Today")
    public func dayLabel(index: Int = -1) -> String {
        if index == 0 || Calendar.current.isDateInToday(self) {
            return "Today"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: self)
    }

    /// Format as short date (e.g., "Apr 1")
    public func shortDate() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: self)
    }

    /// Format as current time (e.g., "3:45 PM")
    public static func currentTimeString(timezone: TimeZone = .current) -> String {
        Date().timeString(timezone: timezone)
    }
}
