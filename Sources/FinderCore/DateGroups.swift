import Foundation

/// Headers for "Group by Date": Today, Yesterday, Last 3 Days, then the widest period the date falls in.
public enum DateGroup {
    public static func label(for date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        if days <= 0 { return "Today" }
        if days == 1 { return "Yesterday" }
        if days <= 3 { return "Last 3 Days" }
        if calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear) { return "Earlier This Week" }
        if calendar.isDate(date, equalTo: now, toGranularity: .month) { return "Earlier This Month" }
        if calendar.isDate(date, equalTo: now, toGranularity: .year) { return "Earlier This Year" }
        return "Before This Year"
    }
}
