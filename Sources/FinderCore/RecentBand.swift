import Foundation

/// Bands for Recent Locations. Dates older than 7 days have no band.
public enum RecentBand {
    public static let order = ["Last 3 Hours", "Last 12 Hours", "Earlier Today", "Yesterday", "2 Days Ago", "3 Days Ago", "Last 7 Days"]

    public static func label(for date: Date, now: Date = Date(), calendar: Calendar = .current) -> String? {
        let secs = now.timeIntervalSince(date)
        if secs < 3 * 3600 { return order[0] }
        if secs < 12 * 3600 { return order[1] }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        switch days {
        case ...0: return order[2]
        case 1: return order[3]
        case 2: return order[4]
        case 3: return order[5]
        case 4...7: return order[6]
        default: return nil
        }
    }
}
