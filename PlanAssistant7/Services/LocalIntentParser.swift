import Foundation

struct LocalIntentParser {
    func parse(
        text rawText: String,
        now: Date = .now,
        timezoneIdentifier: String = PlanDateFormatter.defaultTimezoneIdentifier,
        contextEvents: [ContextEvent]
    ) -> IntentResponse {
        let text = rawText.trimmedPlanText

        guard !text.isEmpty else {
            return IntentResponse(
                intent: .clarify,
                draft: nil,
                targetEventID: nil,
                candidateEventIDs: [],
                question: "想记录什么日程？",
                message: nil,
                reason: "text 为空。",
                confidence: 0,
                ambiguities: [],
                needsConfirmation: true
            )
        }

        if isUnsupported(text) {
            return IntentResponse(
                intent: .unsupported,
                draft: nil,
                targetEventID: nil,
                candidateEventIDs: [],
                question: nil,
                message: "当前本地版只支持创建或取消单次日程。",
                reason: "本地解析暂不支持修改、延期、完成或重复日程。",
                confidence: 0.42,
                ambiguities: ["本地版暂不支持复杂操作"],
                needsConfirmation: true
            )
        }

        if isCancelIntent(text) {
            return parseCancel(text: text, contextEvents: contextEvents)
        }

        if needsDateClarificationForLookup(text) {
            return IntentResponse(
                intent: .clarify,
                draft: nil,
                targetEventID: nil,
                candidateEventIDs: [],
                question: "我还不能查询实时活动日期。请补充活动的具体日期，或直接说“5月29日提醒我买票”。",
                message: nil,
                reason: "输入需要查询外部活动日期，本地解析无法可靠确定日期。",
                confidence: 0.62,
                ambiguities: ["缺少可写入日程的确切日期"],
                needsConfirmation: true
            )
        }

        return parseCreate(
            text: text,
            now: now,
            timezoneIdentifier: timezoneIdentifier
        )
    }

    private func parseCancel(text: String, contextEvents: [ContextEvent]) -> IntentResponse {
        let normalizedText = normalizedForMatching(text)
        let candidates = contextEvents.filter { event in
            let title = normalizedForMatching(event.title)
            return !title.isEmpty && (normalizedText.contains(title) || title.contains(normalizedText))
        }

        if candidates.isEmpty {
            return IntentResponse(
                intent: .clarify,
                draft: nil,
                targetEventID: nil,
                candidateEventIDs: [],
                question: "没有匹配到要取消的日程，请补充标题或时间。",
                message: nil,
                reason: "取消目标未匹配。",
                confidence: 0.38,
                ambiguities: ["未找到候选日程"],
                needsConfirmation: true
            )
        }

        let ids = candidates.map(\.id)
        return IntentResponse(
            intent: .cancel,
            draft: nil,
            targetEventID: ids.count == 1 ? ids[0] : nil,
            candidateEventIDs: ids,
            question: nil,
            message: nil,
            reason: "本地标题匹配。",
            confidence: ids.count == 1 ? 0.86 : 0.62,
            ambiguities: ids.count > 1 ? ["匹配到多个候选"] : [],
            needsConfirmation: true
        )
    }

    private func parseCreate(text: String, now: Date, timezoneIdentifier: String) -> IntentResponse {
        let calendar = PlanDateFormatter.zhCalendar
        let relativeScheduledAt = resolvedRelativeScheduledDate(for: text, now: now, calendar: calendar)
        let day = relativeScheduledAt.map { calendar.startOfDay(for: $0) } ?? resolvedDay(for: text, now: now, calendar: calendar)
        let time = resolvedTime(for: text)
        let scheduledAt = relativeScheduledAt ?? time.map { time in
            calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: day) ?? day
        }
        let endAt = scheduledAt.flatMap { calendar.date(byAdding: .hour, value: 1, to: $0) }
        let kind: EventKind = isAlarmIntent(text) ? .alarm : .calendar
        let reminderPolicy = relativeScheduledAt == nil ? resolvedReminderPolicy(for: text, kind: kind) : .atTime
        let title = resolvedTitle(from: text, fallbackKind: kind)
        let ambiguities = text.contains("每天") || text.contains("每周") || text.contains("每月")
            ? ["本地版暂不支持重复日程，已按单次事件处理"]
            : []

        let draft = DraftEvent(
            kind: kind,
            rawText: text,
            title: title,
            taskDate: PlanDateFormatter.isoString(from: day, timezoneIdentifier: timezoneIdentifier),
            taskTime: scheduledAt.map { PlanDateFormatter.isoString(from: $0, timezoneIdentifier: timezoneIdentifier) },
            endAt: endAt.map { PlanDateFormatter.isoString(from: $0, timezoneIdentifier: timezoneIdentifier) },
            reminderPolicy: reminderPolicy,
            notes: "",
            timezoneIdentifier: timezoneIdentifier
        )

        return IntentResponse(
            intent: .create,
            draft: draft,
            targetEventID: nil,
            candidateEventIDs: [],
            question: nil,
            message: nil,
            reason: nil,
            confidence: scheduledAt == nil ? 0.72 : 0.86,
            ambiguities: ambiguities,
            needsConfirmation: true
        )
    }

    private func isUnsupported(_ text: String) -> Bool {
        ["改到", "修改", "延期", "推迟", "提前到", "完成", "每天", "每周", "每月"].contains { keyword in
            text.contains(keyword)
        } && !text.contains("提醒")
    }

    private func isCancelIntent(_ text: String) -> Bool {
        ["取消", "删除", "删掉", "不要"].contains { text.contains($0) }
    }

    private func isAlarmIntent(_ text: String) -> Bool {
        ["闹钟", "叫醒", "叫我起床", "设个闹钟"].contains { text.contains($0) }
    }

    private func resolvedDay(for text: String, now: Date, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: now)
        if let explicitDate = explicitDate(in: text, now: now, calendar: calendar) {
            return explicitDate
        }
        if text.contains("后天") {
            return calendar.date(byAdding: .day, value: 2, to: start) ?? start
        }
        if text.contains("明天") || text.contains("明早") {
            return calendar.date(byAdding: .day, value: 1, to: start) ?? start
        }
        if let weekday = nextWeekday(in: text), let date = nextWeekdayDate(weekday, from: now, calendar: calendar) {
            return date
        }
        return start
    }

    private func nextWeekday(in text: String) -> Int? {
        guard text.contains("下周") || text.contains("下星期") else { return nil }
        let mapping: [(String, Int)] = [
            ("一", 2), ("二", 3), ("三", 4), ("四", 5), ("五", 6), ("六", 7), ("日", 1), ("天", 1)
        ]
        return mapping.first { text.contains("下周\($0.0)") || text.contains("下星期\($0.0)") }?.1
    }

    private func nextWeekdayDate(_ weekday: Int, from now: Date, calendar: Calendar) -> Date? {
        let currentWeekday = calendar.component(.weekday, from: now)
        let daysUntilNextWeek = (8 - currentWeekday) % 7
        let nextWeekStart = calendar.date(byAdding: .day, value: daysUntilNextWeek == 0 ? 7 : daysUntilNextWeek, to: calendar.startOfDay(for: now))
        return nextWeekStart.flatMap { calendar.date(byAdding: .day, value: weekday - 1, to: $0) }
    }

    private func resolvedTime(for text: String) -> (hour: Int, minute: Int)? {
        if let match = firstMatch(in: text, pattern: #"(\d{1,2})\s*[:：]\s*(\d{1,2})"#),
           let hour = Int(match[1]),
           let minute = Int(match[2]) {
            return adjustedTime(hour: hour, minute: minute, in: text)
        }

        if let match = firstMatch(in: text, pattern: #"(\d{1,2})\s*点\s*半"#),
           let hour = Int(match[1]) {
            return adjustedTime(hour: hour, minute: 30, in: text)
        }

        if let match = firstMatch(in: text, pattern: #"(\d{1,2})\s*点\s*(\d{1,2})?"#),
           let hour = Int(match[1]) {
            let minute = match.count > 2 ? Int(match[2]) ?? 0 : 0
            return adjustedTime(hour: hour, minute: minute, in: text)
        }

        if let match = firstMatch(in: text, pattern: #"([零〇一二两三四五六七八九十]+)\s*点\s*半"#),
           let hour = chineseNumber(match[1]) {
            return adjustedTime(hour: hour, minute: 30, in: text)
        }

        if let match = firstMatch(in: text, pattern: #"([零〇一二两三四五六七八九十]+)\s*点"#),
           let hour = chineseNumber(match[1]) {
            return adjustedTime(hour: hour, minute: 0, in: text)
        }

        if text.contains("今晚") {
            return (20, 0)
        }
        if text.contains("明早") || text.contains("早上") {
            return (8, 0)
        }
        return nil
    }

    private func resolvedRelativeScheduledDate(for text: String, now: Date, calendar: Calendar) -> Date? {
        let normalized = text.replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
        if normalized.range(of: #"(一会儿|一会|待会儿|待会)后?"#, options: .regularExpression) != nil {
            return calendar.date(byAdding: .minute, value: 5, to: now)
        }

        if normalized.range(of: #"半(个)?小时后"#, options: .regularExpression) != nil {
            return calendar.date(byAdding: .minute, value: 30, to: now)
        }

        guard let match = firstMatch(in: normalized, pattern: #"([0-9一二两三四五六七八九十]+)(分钟|分|小时|个小时)后"#),
              let fullMatch = match.first,
              let delay = Int(match[1]) ?? chineseNumber(match[1])
        else {
            return nil
        }

        if let range = normalized.range(of: fullMatch) {
            let prefix = normalized[..<range.lowerBound].suffix(2)
            guard !prefix.contains("提前") else { return nil }
        }

        let minutes = match[2].contains("小时") ? delay * 60 : delay
        return calendar.date(byAdding: .minute, value: max(minutes, 1), to: now)
    }

    private func adjustedTime(hour rawHour: Int, minute: Int, in text: String) -> (hour: Int, minute: Int) {
        var hour = rawHour
        if (text.contains("下午") || text.contains("晚上") || text.contains("今晚")) && hour < 12 {
            hour += 12
        }
        if text.contains("中午") && hour < 11 {
            hour += 12
        }
        return (min(max(hour, 0), 23), min(max(minute, 0), 59))
    }

    private func resolvedReminderPolicy(for text: String, kind: EventKind) -> ReminderPolicy {
        if text.contains("不提醒") {
            return .none
        }
        if text.contains("准时") || text.contains("到点") || kind == .alarm {
            return .atTime
        }
        if let match = firstMatch(in: text, pattern: #"提前\s*([0-9一二两三四五六七八九十]+)\s*(分钟|小时|天|日)"#) {
            let value = Int(match[1]) ?? chineseNumber(match[1]) ?? 60
            let minutes: Int
            switch match[2] {
            case "小时":
                minutes = value * 60
            case "天", "日":
                minutes = value * 24 * 60
            default:
                minutes = value
            }
            return ReminderPolicy(kind: .customOffset, offsetMinutes: max(minutes, 1))
        }
        return .defaultCalendar
    }

    private func resolvedTitle(from text: String, fallbackKind: EventKind) -> String {
        var title = text
        let patterns = [
            #"\d{4}\s*年\s*\d{1,2}\s*月\s*\d{1,2}\s*[日号]?"#,
            #"\d{4}\s*[-/.]\s*\d{1,2}\s*[-/.]\s*\d{1,2}"#,
            #"\d{1,2}\s*月\s*\d{1,2}\s*[日号]?"#,
            #"\d{1,2}\s*[/\.]\s*\d{1,2}"#,
            #"今天|明天|后天|今晚|明早|下周[一二三四五六日天]|下星期[一二三四五六日天]"#,
            #"上午|下午|晚上|早上|中午"#,
            #"(一会儿|一会|待会儿|待会)后?"#,
            #"半(个)?小时后"#,
            #"[0-9一二两三四五六七八九十]+(分钟|分|小时|个小时)后"#,
            #"\d{1,2}\s*[:：]\s*\d{1,2}"#,
            #"\d{1,2}\s*点\s*半?"#,
            #"[零〇一二两三四五六七八九十]+\s*点\s*半?"#,
            #"提前\s*[0-9一二两三四五六七八九十]+\s*(分钟|小时|天|日)"#,
            #"提醒我|提醒|帮我|请|设置|设个|闹钟|叫醒|叫我起床|叫我"#,
            #"不提醒|准时提醒|准时"#,
            #"今年|明年"#
        ]
        for pattern in patterns {
            title = title.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        title = title.replacingOccurrences(of: #"^[，。、“”\s的]+|[，。、“”\s]+$"#, with: "", options: .regularExpression)
        return title.isEmpty ? (fallbackKind == .alarm ? "起床" : "新日程") : title
    }

    private func needsDateClarificationForLookup(_ text: String) -> Bool {
        let lookupKeywords = ["什么时候", "哪天", "几号", "查一下", "查查", "看看"]
        guard lookupKeywords.contains(where: text.contains) else { return false }
        return !containsResolvableDate(in: text)
    }

    private func containsResolvableDate(in text: String) -> Bool {
        let relativeDateKeywords = ["今天", "明天", "后天", "今晚", "明早", "下周", "下星期"]
        if relativeDateKeywords.contains(where: text.contains) {
            return true
        }

        let datePatterns = [
            #"\d{4}\s*年\s*\d{1,2}\s*月\s*\d{1,2}\s*[日号]?"#,
            #"\d{4}\s*[-/.]\s*\d{1,2}\s*[-/.]\s*\d{1,2}"#,
            #"\d{1,2}\s*月\s*\d{1,2}\s*[日号]?"#,
            #"\d{1,2}\s*[/\.]\s*\d{1,2}"#
        ]
        return datePatterns.contains { firstMatch(in: text, pattern: $0) != nil }
    }

    private func explicitDate(in text: String, now: Date, calendar: Calendar) -> Date? {
        if let match = firstMatch(in: text, pattern: #"(\d{4})\s*年\s*(\d{1,2})\s*月\s*(\d{1,2})\s*[日号]?"#),
           let year = Int(match[1]),
           let month = Int(match[2]),
           let day = Int(match[3]) {
            return date(year: year, month: month, day: day, calendar: calendar)
        }

        if let match = firstMatch(in: text, pattern: #"(\d{4})\s*[-/.]\s*(\d{1,2})\s*[-/.]\s*(\d{1,2})"#),
           let year = Int(match[1]),
           let month = Int(match[2]),
           let day = Int(match[3]) {
            return date(year: year, month: month, day: day, calendar: calendar)
        }

        let currentYear = calendar.component(.year, from: now)
        if let match = firstMatch(in: text, pattern: #"(\d{1,2})\s*月\s*(\d{1,2})\s*[日号]?"#),
           let month = Int(match[1]),
           let day = Int(match[2]) {
            return date(year: currentYear, month: month, day: day, calendar: calendar)
        }

        if let match = firstMatch(in: text, pattern: #"(\d{1,2})\s*[/\.]\s*(\d{1,2})"#),
           let month = Int(match[1]),
           let day = Int(match[2]) {
            return date(year: currentYear, month: month, day: day, calendar: calendar)
        }

        return nil
    }

    private func date(year: Int, month: Int, day: Int, calendar: Calendar) -> Date? {
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = month
        components.day = day

        guard let date = calendar.date(from: components) else { return nil }
        let resolved = calendar.dateComponents([.year, .month, .day], from: date)
        guard resolved.year == year, resolved.month == month, resolved.day == day else { return nil }
        return calendar.startOfDay(for: date)
    }

    private func normalizedForMatching(_ text: String) -> String {
        text.replacingOccurrences(
            of: #"取消|删除|删掉|帮我|请|一下|这个|那个|日程|闹钟|[，。、“”\s]"#,
            with: "",
            options: .regularExpression
        )
    }

    private func firstMatch(in text: String, pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        return (0..<match.numberOfRanges).compactMap { index in
            let matchRange = match.range(at: index)
            guard matchRange.location != NSNotFound, let range = Range(matchRange, in: text) else { return nil }
            return String(text[range])
        }
    }

    private func chineseNumber(_ text: String) -> Int? {
        if text == "十" { return 10 }
        let values: [Character: Int] = [
            "零": 0, "〇": 0, "一": 1, "二": 2, "两": 2, "三": 3, "四": 4,
            "五": 5, "六": 6, "七": 7, "八": 8, "九": 9
        ]
        if text.contains("十") {
            let parts = text.split(separator: "十", omittingEmptySubsequences: false)
            let tens = parts.first?.first.flatMap { values[$0] } ?? 1
            let ones = parts.count > 1 ? parts[1].first.flatMap { values[$0] } ?? 0 : 0
            return tens * 10 + ones
        }
        return text.reduce(0) { partial, character in
            partial * 10 + (values[character] ?? 0)
        }
    }
}
