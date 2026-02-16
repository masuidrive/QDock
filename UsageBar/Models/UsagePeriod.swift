import Foundation

enum UsagePeriod: String, CaseIterable, Identifiable {
    case today = "Today"
    case yesterday = "Yesterday"
    case last7Days = "Last 7 Days"
    case last30Days = "Last 30 Days"
    case thisMonth = "This Month"

    var id: String { rawValue }

    /// Returns the start date for this period
    var startDate: Date {
        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)

        switch self {
        case .today:
            return startOfToday
        case .yesterday:
            return calendar.date(byAdding: .day, value: -1, to: startOfToday)!
        case .last7Days:
            return calendar.date(byAdding: .day, value: -7, to: startOfToday)!
        case .last30Days:
            return calendar.date(byAdding: .day, value: -30, to: startOfToday)!
        case .thisMonth:
            return calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
        }
    }

    /// Returns the end date for this period
    var endDate: Date {
        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)

        switch self {
        case .yesterday:
            return startOfToday
        default:
            // End of today (start of tomorrow)
            return calendar.date(byAdding: .day, value: 1, to: startOfToday)!
        }
    }

    /// The appropriate bucket width for API calls
    var bucketWidth: String {
        switch self {
        case .today, .yesterday:
            return "1h"
        case .last7Days:
            return "1d"
        case .last30Days, .thisMonth:
            return "1d"
        }
    }
}
