import Foundation

enum PlanDateFormatter {
    static let defaultTimezoneIdentifier = "Asia/Shanghai"

    static var defaultTimezone: TimeZone {
        TimeZone(identifier: defaultTimezoneIdentifier) ?? .current
    }

    static var zhCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "zh_CN")
        calendar.timeZone = defaultTimezone
        return calendar
    }

    static func isoString(from date: Date, timezoneIdentifier: String = defaultTimezoneIdentifier) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withColonSeparatorInTimeZone]
        formatter.timeZone = TimeZone(identifier: timezoneIdentifier) ?? defaultTimezone
        return formatter.string(from: date)
    }

    static func date(from isoString: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withColonSeparatorInTimeZone]
        if let date = formatter.date(from: isoString) {
            return date
        }

        let localDateTimeFormatter = DateFormatter()
        localDateTimeFormatter.locale = Locale(identifier: "zh_CN")
        localDateTimeFormatter.timeZone = defaultTimezone
        localDateTimeFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        if let date = localDateTimeFormatter.date(from: isoString) {
            return date
        }

        let localDayFormatter = DateFormatter()
        localDayFormatter.locale = Locale(identifier: "zh_CN")
        localDayFormatter.timeZone = defaultTimezone
        localDayFormatter.dateFormat = "yyyy-MM-dd"
        return localDayFormatter.date(from: isoString)
    }

    static func optionalDate(from isoString: String?) -> Date?? {
        guard let isoString else { return .some(nil) }
        guard let date = date(from: isoString) else { return nil }
        return .some(date)
    }

    static func startOfDay(for date: Date, calendar: Calendar = zhCalendar) -> Date {
        calendar.startOfDay(for: date)
    }

    static func friendlyDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = defaultTimezone
        formatter.dateFormat = "M月d日 EEEE"
        return formatter.string(from: date)
    }

    static func compactDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = defaultTimezone
        formatter.dateFormat = "yyyy年M月d日"
        return formatter.string(from: date)
    }

    static func clockText(_ date: Date?) -> String {
        guard let date else { return "全天" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = defaultTimezone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    static func dateTimeText(_ date: Date?) -> String {
        guard let date else { return "全天" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = defaultTimezone
        formatter.dateFormat = "yyyy年M月d日 HH:mm"
        return formatter.string(from: date)
    }

    static func weekdayText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = defaultTimezone
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }

    static func greeting(for date: Date = .now) -> String {
        let hour = zhCalendar.component(.hour, from: date)
        switch hour {
        case 5..<11:
            return "早上好"
        case 11..<14:
            return "中午好"
        case 14..<18:
            return "下午好"
        default:
            return "晚上好"
        }
    }
}

extension String {
    var trimmedPlanText: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
