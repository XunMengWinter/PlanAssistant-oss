import Foundation
import SwiftData

enum EventKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case calendar
    case alarm

    var id: String { rawValue }

    var title: String {
        switch self {
        case .calendar:
            "日程"
        case .alarm:
            "闹钟"
        }
    }
}

enum IntentType: String, Codable, Sendable {
    case create
    case cancel
    case clarify
    case unsupported
}

enum ScheduleQueryStatus: String, Codable, Sendable {
    case answer
    case clarify
    case unsupported
}

enum AssistantResponseKind: String, Codable, Sendable {
    case intent
    case query
}

enum ReminderPolicyKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case none
    case atTime
    case tenMinutesBefore
    case customOffset

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none:
            "不提醒"
        case .atTime:
            "准时提醒"
        case .tenMinutesBefore:
            "提前 10 分钟"
        case .customOffset:
            "自定义提醒"
        }
    }
}

struct ReminderPolicy: Codable, Hashable, Sendable {
    var kind: ReminderPolicyKind
    var offsetMinutes: Int?

    static let defaultCalendar = ReminderPolicy(kind: .tenMinutesBefore, offsetMinutes: nil)
    static let atTime = ReminderPolicy(kind: .atTime, offsetMinutes: nil)
    static let none = ReminderPolicy(kind: .none, offsetMinutes: nil)
    static let customDefault = ReminderPolicy(kind: .customOffset, offsetMinutes: 60)

    var resolvedOffsetMinutes: Int? {
        switch kind {
        case .none:
            nil
        case .atTime:
            0
        case .tenMinutesBefore:
            10
        case .customOffset:
            max(offsetMinutes ?? 60, 1)
        }
    }

    var displayText: String {
        switch kind {
        case .none:
            return "不提醒"
        case .atTime:
            return "准时提醒"
        case .tenMinutesBefore:
            return "提前 10 分钟"
        case .customOffset:
            let minutes = max(offsetMinutes ?? 60, 1)
            if minutes.isMultiple(of: 24 * 60) {
                return "提前 \(minutes / (24 * 60)) 天"
            }
            if minutes.isMultiple(of: 60) {
                return "提前 \(minutes / 60) 小时"
            }
            return "提前 \(minutes) 分钟"
        }
    }
}

struct DraftEvent: Codable, Hashable, Sendable {
    var kind: EventKind
    var rawText: String
    var title: String
    var taskDate: String
    var taskTime: String?
    var endAt: String?
    var reminderPolicy: ReminderPolicy
    var notes: String
    var timezoneIdentifier: String
}

struct ContextEvent: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var kind: EventKind?
    var title: String
    var taskDate: String
    var scheduledAt: String?
    var endAt: String?
    var notes: String?
    var timezoneIdentifier: String?

    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case title
        case taskDate
        case scheduledAt
        case endAt
        case notes
        case timezoneIdentifier
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(kind, forKey: .kind)
        try container.encode(title, forKey: .title)
        try container.encode(taskDate, forKey: .taskDate)
        try container.encode(scheduledAt, forKey: .scheduledAt)
        try container.encode(endAt, forKey: .endAt)
        try container.encodeIfPresent(notes, forKey: .notes)
        try container.encodeIfPresent(timezoneIdentifier, forKey: .timezoneIdentifier)
    }
}

struct QueryContextEvent: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var kind: EventKind?
    var title: String
    var taskDate: String
    var scheduledAt: String?
    var endAt: String?
    var notes: String?
    var timezoneIdentifier: String?
    var isCompleted: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case title
        case taskDate
        case scheduledAt
        case endAt
        case notes
        case timezoneIdentifier
        case isCompleted
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(kind, forKey: .kind)
        try container.encode(title, forKey: .title)
        try container.encode(taskDate, forKey: .taskDate)
        try container.encode(scheduledAt, forKey: .scheduledAt)
        try container.encode(endAt, forKey: .endAt)
        try container.encodeIfPresent(notes, forKey: .notes)
        try container.encodeIfPresent(timezoneIdentifier, forKey: .timezoneIdentifier)
        try container.encode(isCompleted, forKey: .isCompleted)
    }
}

struct IntentResponse: Codable, Hashable, Sendable {
    var intent: IntentType
    var draft: DraftEvent?
    var targetEventID: String?
    var candidateEventIDs: [String]
    var question: String?
    var message: String?
    var reason: String?
    var confidence: Double
    var ambiguities: [String]
    var needsConfirmation: Bool
}

struct ScheduleIntentRequest: Encodable, Sendable {
    var text: String
    var now: String
    var timezone: String
    var locale: String?
    var context: ScheduleIntentContext
}

struct ScheduleIntentContext: Encodable, Sendable {
    var events: [ContextEvent]
}

struct ScheduleQueryRequest: Encodable, Sendable {
    var text: String
    var now: String
    var timezone: String
    var locale: String?
    var context: ScheduleQueryContext
}

struct ScheduleQueryContext: Encodable, Sendable {
    var events: [QueryContextEvent]
}

struct ScheduleQueryResponse: Codable, Hashable, Sendable {
    var status: ScheduleQueryStatus
    var title: String
    var answer: String?
    var suggestions: [String]
    var referencedEventIDs: [String]
    var rangeStart: String?
    var rangeEnd: String?
    var question: String?
    var message: String?
    var confidence: Double
    var ambiguities: [String]
}

struct AssistantRequest: Encodable, Sendable {
    var text: String
    var now: String
    var timezone: String
    var locale: String?
    var context: ScheduleQueryContext
}

struct AssistantResponse: Codable, Hashable, Sendable {
    var type: AssistantResponseKind
    var intent: IntentResponse?
    var query: ScheduleQueryResponse?
    var routeReason: String?
    var routeConfidence: Double
}

struct APIErrorResponse: Decodable, Sendable {
    var error: APIErrorBody
}

struct APIErrorBody: Decodable, Sendable {
    var code: String
    var message: String
}

@Model
final class SavedEvent {
    @Attribute(.unique) var id: String
    var kindRawValue: String
    var rawText: String
    var title: String
    var taskDate: Date
    var scheduledAt: Date?
    var endAt: Date?
    var notes: String
    var timezoneIdentifier: String
    var reminderPolicyKindRawValue: String
    var reminderOffsetMinutes: Int?
    var calendarEventIdentifier: String?
    var calendarExternalIdentifier: String?
    var alarmID: String?
    var isCompleted: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        kind: EventKind,
        rawText: String,
        title: String,
        taskDate: Date,
        scheduledAt: Date?,
        endAt: Date?,
        notes: String,
        timezoneIdentifier: String,
        reminderPolicy: ReminderPolicy,
        calendarEventIdentifier: String? = nil,
        calendarExternalIdentifier: String? = nil,
        alarmID: String? = nil,
        isCompleted: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.kindRawValue = kind.rawValue
        self.rawText = rawText
        self.title = title
        self.taskDate = taskDate
        self.scheduledAt = scheduledAt
        self.endAt = endAt
        self.notes = notes
        self.timezoneIdentifier = timezoneIdentifier
        self.reminderPolicyKindRawValue = reminderPolicy.kind.rawValue
        self.reminderOffsetMinutes = reminderPolicy.offsetMinutes
        self.calendarEventIdentifier = calendarEventIdentifier
        self.calendarExternalIdentifier = calendarExternalIdentifier
        self.alarmID = alarmID
        self.isCompleted = isCompleted
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var kind: EventKind {
        get { EventKind(rawValue: kindRawValue) ?? .calendar }
        set { kindRawValue = newValue.rawValue }
    }

    var reminderPolicy: ReminderPolicy {
        get {
            ReminderPolicy(
                kind: ReminderPolicyKind(rawValue: reminderPolicyKindRawValue) ?? .tenMinutesBefore,
                offsetMinutes: reminderOffsetMinutes
            )
        }
        set {
            reminderPolicyKindRawValue = newValue.kind.rawValue
            reminderOffsetMinutes = newValue.offsetMinutes
        }
    }
}

extension SavedEvent {
    convenience init?(draft: DraftEvent) {
        guard
            let taskDate = PlanDateFormatter.date(from: draft.taskDate),
            let scheduledAt = PlanDateFormatter.optionalDate(from: draft.taskTime),
            let endAt = PlanDateFormatter.optionalDate(from: draft.endAt)
        else {
            return nil
        }

        self.init(
            kind: draft.kind,
            rawText: draft.rawText,
            title: draft.title,
            taskDate: taskDate,
            scheduledAt: scheduledAt,
            endAt: endAt,
            notes: draft.notes,
            timezoneIdentifier: draft.timezoneIdentifier,
            reminderPolicy: draft.reminderPolicy
        )
    }

    var contextEvent: ContextEvent {
        ContextEvent(
            id: id,
            kind: kind,
            title: title,
            taskDate: PlanDateFormatter.isoString(from: taskDate, timezoneIdentifier: timezoneIdentifier),
            scheduledAt: scheduledAt.map { PlanDateFormatter.isoString(from: $0, timezoneIdentifier: timezoneIdentifier) },
            endAt: endAt.map { PlanDateFormatter.isoString(from: $0, timezoneIdentifier: timezoneIdentifier) },
            notes: notes,
            timezoneIdentifier: timezoneIdentifier
        )
    }

    var queryContextEvent: QueryContextEvent {
        QueryContextEvent(
            id: id,
            kind: kind,
            title: title,
            taskDate: PlanDateFormatter.isoString(from: taskDate, timezoneIdentifier: timezoneIdentifier),
            scheduledAt: scheduledAt.map { PlanDateFormatter.isoString(from: $0, timezoneIdentifier: timezoneIdentifier) },
            endAt: endAt.map { PlanDateFormatter.isoString(from: $0, timezoneIdentifier: timezoneIdentifier) },
            notes: notes,
            timezoneIdentifier: timezoneIdentifier,
            isCompleted: isCompleted
        )
    }
}
