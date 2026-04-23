import AlarmKit
import AVFAudio
import EventKit
import Foundation
import Observation
import Speech
import SwiftUI

enum PlanSystemError: LocalizedError {
    case calendarAccessDenied
    case defaultCalendarMissing
    case alarmAccessDenied
    case alarmTimeMissing
    case alarmFireDateInvalid
    case alarmLimitReached
    case alarmKitUnavailable
    case alarmSchedulingFailed(String)
    case speechAccessDenied
    case microphoneAccessDenied
    case recognizerUnavailable
    case audioInputUnavailable

    var errorDescription: String? {
        switch self {
        case .calendarAccessDenied:
            "未获得日历完整访问权限。"
        case .defaultCalendarMissing:
            "没有可写入的默认系统日历。"
        case .alarmAccessDenied:
            "未获得闹钟权限。"
        case .alarmTimeMissing:
            "闹钟需要具体时间。"
        case .alarmFireDateInvalid:
            "闹钟时间必须晚于当前时间。"
        case .alarmLimitReached:
            "系统闹钟数量已达上限，请先删除一些闹钟后再试。"
        case .alarmKitUnavailable:
            "AlarmKit 暂时不可用。请确认设备为 iOS 26 以上、App 已重新安装，并且签名配置支持 AlarmKit。"
        case .alarmSchedulingFailed(let message):
            "闹钟保存失败：\(message)"
        case .speechAccessDenied:
            "未获得语音识别权限。"
        case .microphoneAccessDenied:
            "未获得麦克风权限。"
        case .recognizerUnavailable:
            "当前设备暂不可用中文语音识别。"
        case .audioInputUnavailable:
            "当前设备没有可用的麦克风输入，请检查模拟器或设备的音频输入。"
        }
    }
}

struct CalendarWriteIdentifiers {
    var eventIdentifier: String?
    var externalIdentifier: String?
}

@available(iOS 26.0, *)
struct PlanAlarmMetadata: AlarmMetadata {
    var savedEventID: String
    var title: String
}

@MainActor
@Observable
final class CalendarService {
    @ObservationIgnored private let eventStore = EKEventStore()
    private(set) var authorizationStatus: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)
    private(set) var lastErrorMessage: String?

    var hasFullAccess: Bool {
        authorizationStatus == .fullAccess
    }

    var statusText: String {
        switch authorizationStatus {
        case .notDetermined:
            "日历 可请求"
        case .restricted:
            "日历 受限制"
        case .denied:
            "日历 未授权"
        case .fullAccess:
            "日历 已授权"
        case .writeOnly:
            "日历 仅写入"
        @unknown default:
            "日历 未知"
        }
    }

    func refreshAuthorizationStatus() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
    }

    func requestAccessOnLaunch() async {
        do {
            _ = try await requestFullAccess()
        } catch {
            lastErrorMessage = error.localizedDescription
            refreshAuthorizationStatus()
        }
    }

    func requestFullAccess() async throws -> Bool {
        let granted = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
            eventStore.requestFullAccessToEvents { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
        refreshAuthorizationStatus()
        return granted
    }

    func saveCalendarEvent(for savedEvent: SavedEvent) throws -> CalendarWriteIdentifiers {
        refreshAuthorizationStatus()
        guard hasFullAccess else { throw PlanSystemError.calendarAccessDenied }
        guard let calendar = eventStore.defaultCalendarForNewEvents else { throw PlanSystemError.defaultCalendarMissing }

        let event = EKEvent(eventStore: eventStore)
        event.calendar = calendar
        event.title = savedEvent.title
        event.notes = composedNotes(for: savedEvent)
        event.timeZone = TimeZone(identifier: savedEvent.timezoneIdentifier) ?? PlanDateFormatter.defaultTimezone

        if let scheduledAt = savedEvent.scheduledAt {
            event.isAllDay = false
            event.startDate = scheduledAt
            event.endDate = savedEvent.endAt ?? scheduledAt.addingTimeInterval(3600)
        } else {
            event.isAllDay = true
            event.startDate = PlanDateFormatter.startOfDay(for: savedEvent.taskDate)
            event.endDate = PlanDateFormatter.zhCalendar.date(byAdding: .day, value: 1, to: event.startDate)
        }

        if let offset = savedEvent.reminderPolicy.resolvedOffsetMinutes {
            event.addAlarm(EKAlarm(relativeOffset: TimeInterval(-offset * 60)))
        }

        try eventStore.save(event, span: .thisEvent)
        return CalendarWriteIdentifiers(
            eventIdentifier: event.eventIdentifier,
            externalIdentifier: event.calendarItemExternalIdentifier
        )
    }

    func deleteCalendarEvent(identifier: String?) throws {
        guard let identifier else { return }
        refreshAuthorizationStatus()
        guard hasFullAccess else { throw PlanSystemError.calendarAccessDenied }
        guard let event = eventStore.event(withIdentifier: identifier) else { return }
        try eventStore.remove(event, span: .thisEvent)
    }

    func calendarEvent(identifier: String?) -> EKEvent? {
        refreshAuthorizationStatus()
        guard hasFullAccess, let identifier else { return nil }
        return eventStore.event(withIdentifier: identifier)
    }

    func locallyMissingCalendarEventIDs(from savedEvents: [SavedEvent]) -> Set<String> {
        refreshAuthorizationStatus()
        guard hasFullAccess else { return [] }

        let missingIDs = savedEvents.compactMap { event -> String? in
            guard let identifier = event.calendarEventIdentifier else { return nil }
            return eventStore.event(withIdentifier: identifier) == nil ? event.id : nil
        }
        return Set(missingIDs)
    }

    private func composedNotes(for event: SavedEvent) -> String {
        var parts: [String] = []
        if !event.notes.isEmpty {
            parts.append(event.notes)
        }
        parts.append("PlanAssistant 原文：\(event.rawText)")
        parts.append("AppID：\(event.id)")
        return parts.joined(separator: "\n")
    }
}

@MainActor
@Observable
final class AlarmScheduler {
    private(set) var authorizationState: AlarmManager.AuthorizationState = AlarmManager.shared.authorizationState
    private(set) var lastErrorMessage: String?

    var isAuthorized: Bool {
        authorizationState == .authorized
    }

    var statusText: String {
        switch authorizationState {
        case .notDetermined:
            "闹钟 可请求"
        case .denied:
            "闹钟 未授权"
        case .authorized:
            "闹钟 已授权"
        @unknown default:
            "闹钟 未知"
        }
    }

    func refreshAuthorizationState() {
        authorizationState = AlarmManager.shared.authorizationState
    }

    func requestAccessOnLaunch() async {
        do {
            authorizationState = try await AlarmManager.shared.requestAuthorization()
        } catch {
            lastErrorMessage = error.localizedDescription
            refreshAuthorizationState()
        }
    }

    func scheduleAlarm(for savedEvent: SavedEvent) async throws -> String {
        guard let scheduledAt = savedEvent.scheduledAt else { throw PlanSystemError.alarmTimeMissing }
        guard scheduledAt > Date().addingTimeInterval(60) else { throw PlanSystemError.alarmFireDateInvalid }
        try await ensureAuthorized()

        let alarmID = UUID(uuidString: savedEvent.id) ?? UUID()
        let presentation = AlarmPresentation(
            alert: AlarmPresentation.Alert(title: LocalizedStringResource(stringLiteral: savedEvent.title))
        )
        let attributes = AlarmAttributes(
            presentation: presentation,
            metadata: PlanAlarmMetadata(savedEventID: savedEvent.id, title: savedEvent.title),
            tintColor: .orange
        )
        let configuration = AlarmManager.AlarmConfiguration.alarm(
            schedule: .fixed(scheduledAt),
            attributes: attributes
        )
        do {
            let alarm = try await AlarmManager.shared.schedule(id: alarmID, configuration: configuration)
            refreshAuthorizationState()
            return alarm.id.uuidString
        } catch AlarmManager.AlarmError.maximumLimitReached {
            throw PlanSystemError.alarmLimitReached
        } catch where isAlarmKitErrorCodeOne(error) {
            throw PlanSystemError.alarmKitUnavailable
        } catch {
            throw PlanSystemError.alarmSchedulingFailed(error.localizedDescription)
        }
    }

    func cancelAlarm(identifier: String?) throws {
        refreshAuthorizationState()
        guard let identifier, let uuid = UUID(uuidString: identifier) else { return }
        guard isAuthorized else { throw PlanSystemError.alarmAccessDenied }
        guard try hasScheduledAlarm(id: uuid) else { return }
        do {
            try AlarmManager.shared.cancel(id: uuid)
        } catch where isMissingAlarmError(error) {
            return
        }
    }

    private func ensureAuthorized() async throws {
        defer { refreshAuthorizationState() }

        switch AlarmManager.shared.authorizationState {
        case .authorized:
            return
        case .notDetermined:
            let state: AlarmManager.AuthorizationState
            do {
                state = try await AlarmManager.shared.requestAuthorization()
            } catch where isAlarmKitErrorCodeOne(error) {
                throw PlanSystemError.alarmKitUnavailable
            }
            guard state == .authorized else {
                throw PlanSystemError.alarmAccessDenied
            }
        case .denied:
            throw PlanSystemError.alarmAccessDenied
        @unknown default:
            throw PlanSystemError.alarmAccessDenied
        }
    }

    private func isAlarmKitErrorCodeOne(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == "com.apple.AlarmKit.Alarm" && nsError.code == 1
    }

    private func hasScheduledAlarm(id: UUID) throws -> Bool {
        try AlarmManager.shared.alarms.contains { $0.id == id }
    }

    private func isMissingAlarmError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == "com.apple.AlarmKit.Alarm" && nsError.code == 0
    }
}

@MainActor
@Observable
final class SpeechTranscriber {
    private(set) var speechAuthorizationStatus: SFSpeechRecognizerAuthorizationStatus = SFSpeechRecognizer.authorizationStatus()
    private(set) var microphonePermission: AVAudioApplication.recordPermission = AVAudioApplication.shared.recordPermission
    private(set) var isRecording = false
    var transcript = ""
    var lastErrorMessage: String?

    @ObservationIgnored private let audioEngine = AVAudioEngine()
    @ObservationIgnored private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh_CN"))
    @ObservationIgnored private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var recognitionTask: SFSpeechRecognitionTask?

    var canRecord: Bool {
        speechAuthorizationStatus == .authorized && microphonePermission == .granted
    }

    var speechStatusText: String {
        switch speechAuthorizationStatus {
        case .notDetermined:
            "语音 可请求"
        case .denied:
            "语音 未授权"
        case .restricted:
            "语音 受限制"
        case .authorized:
            "语音 已授权"
        @unknown default:
            "语音 未知"
        }
    }

    var microphoneStatusText: String {
        switch microphonePermission {
        case .undetermined:
            "麦克风 可请求"
        case .denied:
            "麦克风 未授权"
        case .granted:
            "麦克风 已授权"
        @unknown default:
            "麦克风 未知"
        }
    }

    func refreshPermissionStatus() {
        speechAuthorizationStatus = SFSpeechRecognizer.authorizationStatus()
        microphonePermission = AVAudioApplication.shared.recordPermission
    }

    func requestPermissionsOnLaunch() async {
        await requestSpeechAuthorization()
        await requestMicrophonePermission()
        refreshPermissionStatus()
    }

    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            do {
                try startRecording()
            } catch {
                lastErrorMessage = error.localizedDescription
                stopRecording()
            }
        }
    }

    func startRecording() throws {
        refreshPermissionStatus()
        guard speechAuthorizationStatus == .authorized else { throw PlanSystemError.speechAccessDenied }
        guard microphonePermission == .granted else { throw PlanSystemError.microphoneAccessDenied }
        guard let speechRecognizer, speechRecognizer.isAvailable else { throw PlanSystemError.recognizerUnavailable }

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        transcript = ""

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                if let result {
                    self?.transcript = result.bestTranscription.formattedString
                }
                if error != nil || result?.isFinal == true {
                    self?.stopRecording()
                }
            }
        }

        let recordingFormat = inputNode.outputFormat(forBus: 0)
        guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
            try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
            recognitionRequest = nil
            recognitionTask?.cancel()
            recognitionTask = nil
            throw PlanSystemError.audioInputUnavailable
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            isRecording = true
            lastErrorMessage = nil
        } catch {
            inputNode.removeTap(onBus: 0)
            recognitionRequest = nil
            recognitionTask?.cancel()
            recognitionTask = nil
            try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
            throw error
        }
    }

    func stopRecording() {
        audioEngine.inputNode.removeTap(onBus: 0)
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        recognitionRequest?.endAudio()
        recognitionTask?.finish()
        recognitionRequest = nil
        recognitionTask = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func requestSpeechAuthorization() async {
        _ = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    private func requestMicrophonePermission() async {
        _ = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}

@MainActor
@Observable
final class IntentParsingService {
    @ObservationIgnored private let parser = LocalIntentParser()
    @ObservationIgnored private let apiClient = ScheduleIntentAPIClient()
    private(set) var lastSourceDescription = "后端待请求"
    private(set) var lastErrorMessage: String?

    func resolve(text: String, contextEvents: [QueryContextEvent]) async -> AssistantResponse {
        do {
            let response = try await apiClient.resolveAssistant(
                text: text.trimmedPlanText,
                contextEvents: contextEvents
            )
            lastSourceDescription = "后端助理"
            lastErrorMessage = nil
            return response
        } catch {
            lastSourceDescription = "后端失败"
            lastErrorMessage = error.localizedDescription
            return AssistantResponse(
                type: .intent,
                intent: IntentResponse(
                    intent: .unsupported,
                    draft: nil,
                    targetEventID: nil,
                    candidateEventIDs: [],
                    question: nil,
                    message: "后端语义路由暂不可用，请稍后再试。",
                    reason: "后端请求失败：\(error.localizedDescription)",
                    confidence: 0,
                    ambiguities: ["未做本地语义分流，避免误判用户意图。"],
                    needsConfirmation: true
                ),
                query: nil,
                routeReason: "后端请求失败",
                routeConfidence: 0
            )
        }
    }

    func parse(text: String, contextEvents: [ContextEvent]) async -> IntentResponse {
        do {
            let response = try await apiClient.parseIntent(
                text: text.trimmedPlanText,
                contextEvents: contextEvents
            )
            lastSourceDescription = "后端解析"
            lastErrorMessage = nil
            return response
        } catch {
            lastSourceDescription = "本地降级"
            lastErrorMessage = error.localizedDescription
            var fallback = parser.parse(
                text: text,
                now: .now,
                timezoneIdentifier: PlanDateFormatter.defaultTimezoneIdentifier,
                contextEvents: contextEvents
            )
            fallback.ambiguities.append("后端请求失败，已使用本地解析：\(error.localizedDescription)")
            return fallback
        }
    }

    func querySchedule(text: String, contextEvents: [QueryContextEvent]) async -> ScheduleQueryResponse {
        do {
            let response = try await apiClient.querySchedule(
                text: text.trimmedPlanText,
                contextEvents: contextEvents
            )
            lastSourceDescription = "后端问答"
            lastErrorMessage = nil
            return response
        } catch {
            lastSourceDescription = "本地降级"
            lastErrorMessage = error.localizedDescription
            var fallback = LocalScheduleQueryResponder().query(
                text: text,
                now: .now,
                timezoneIdentifier: PlanDateFormatter.defaultTimezoneIdentifier,
                contextEvents: contextEvents
            )
            fallback.ambiguities.append("后端请求失败，已使用本地汇总：\(error.localizedDescription)")
            return fallback
        }
    }

    func parseLocally(text: String, contextEvents: [ContextEvent]) -> IntentResponse {
        let response = parser.parse(
            text: text,
            now: .now,
            timezoneIdentifier: PlanDateFormatter.defaultTimezoneIdentifier,
            contextEvents: contextEvents
        )
        lastSourceDescription = "本地解析"
        lastErrorMessage = nil
        return response
    }
}

private struct LocalScheduleQueryResponder {
    func query(
        text rawText: String,
        now: Date,
        timezoneIdentifier: String,
        contextEvents: [QueryContextEvent]
    ) -> ScheduleQueryResponse {
        let text = rawText.trimmedPlanText
        guard !text.isEmpty else {
            return ScheduleQueryResponse(
                status: .clarify,
                title: "需要补充",
                answer: nil,
                suggestions: [],
                referencedEventIDs: [],
                rangeStart: nil,
                rangeEnd: nil,
                question: "想查询哪段时间的日程安排？",
                message: nil,
                confidence: 0.5,
                ambiguities: []
            )
        }

        let range = resolvedRange(for: text, now: now)
        let matchedEvents = contextEvents
            .filter { event in
                guard let eventDate = eventDate(for: event) else { return false }
                return eventDate >= range.start && eventDate < range.end
            }
            .sorted { lhs, rhs in
                (eventDate(for: lhs) ?? .distantFuture) < (eventDate(for: rhs) ?? .distantFuture)
            }

        let activeEvents = matchedEvents.filter { !$0.isCompleted }
        let completedEvents = matchedEvents.filter(\.isCompleted)
        let answer = answerText(
            for: matchedEvents,
            activeCount: activeEvents.count,
            completedCount: completedEvents.count,
            rangeTitle: range.title
        )

        return ScheduleQueryResponse(
            status: .answer,
            title: "\(range.title)安排",
            answer: answer,
            suggestions: suggestions(for: activeEvents, in: text, range: range),
            referencedEventIDs: matchedEvents.map(\.id),
            rangeStart: PlanDateFormatter.isoString(from: range.start, timezoneIdentifier: timezoneIdentifier),
            rangeEnd: PlanDateFormatter.isoString(from: range.end, timezoneIdentifier: timezoneIdentifier),
            question: nil,
            message: nil,
            confidence: 0.66,
            ambiguities: ["后端不可用时，本地仅按已保存日程做基础汇总。"]
        )
    }

    private func resolvedRange(for text: String, now: Date) -> (title: String, start: Date, end: Date) {
        let calendar = PlanDateFormatter.zhCalendar
        let todayStart = calendar.startOfDay(for: now)

        if text.contains("明后天") {
            let start = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? todayStart
            let end = calendar.date(byAdding: .day, value: 2, to: start) ?? start
            return ("明后天", start, end)
        }

        if let dayCount = relativeDayCount(in: text) {
            let end = calendar.date(byAdding: .day, value: dayCount, to: todayStart) ?? todayStart
            return ("接下来 \(dayCount) 天", todayStart, end)
        }

        if text.contains("后天") {
            let start = calendar.date(byAdding: .day, value: 2, to: todayStart) ?? todayStart
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
            return ("后天", start, end)
        }

        if text.contains("明天") {
            let start = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? todayStart
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
            return ("明天", start, end)
        }

        if text.contains("今天") {
            let end = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? todayStart
            return ("今天", todayStart, end)
        }

        if text.contains("下周末") || text.contains("下星期末") {
            let start = weekendStart(from: now, calendar: calendar, weekOffset: 1)
            let end = calendar.date(byAdding: .day, value: 2, to: start) ?? start
            return ("下周末", start, end)
        }

        if text.contains("周末") || text.contains("星期末") {
            let start = weekendStart(from: now, calendar: calendar, weekOffset: 0)
            let end = calendar.date(byAdding: .day, value: 2, to: start) ?? start
            return ("周末", start, end)
        }

        if text.contains("下周") || text.contains("下星期") {
            let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)
            let start = thisWeek.flatMap { calendar.date(byAdding: .weekOfYear, value: 1, to: $0.start) } ?? todayStart
            let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start) ?? start
            return ("下周", start, end)
        }

        if text.contains("本周") || text.contains("这周") || text.contains("这个星期") {
            let interval = calendar.dateInterval(of: .weekOfYear, for: now)
            let start = interval?.start ?? todayStart
            let end = interval?.end ?? (calendar.date(byAdding: .day, value: 7, to: start) ?? start)
            return ("本周", start, end)
        }

        if text.contains("下个月") || text.contains("下月") {
            let thisMonth = calendar.dateInterval(of: .month, for: now)
            let start = thisMonth.flatMap { calendar.date(byAdding: .month, value: 1, to: $0.start) } ?? todayStart
            let end = calendar.date(byAdding: .month, value: 1, to: start) ?? start
            return (monthTitle(for: start), start, end)
        }

        if text.contains("本月") || text.contains("这个月") {
            let interval = calendar.dateInterval(of: .month, for: now)
            let start = interval?.start ?? todayStart
            let end = interval?.end ?? (calendar.date(byAdding: .month, value: 1, to: start) ?? start)
            return (monthTitle(for: start), start, end)
        }

        if let explicitMonth = explicitMonth(in: text) {
            var components = calendar.dateComponents([.year], from: now)
            components.month = explicitMonth
            components.day = 1
            let start = calendar.date(from: components) ?? todayStart
            let end = calendar.date(byAdding: .month, value: 1, to: start) ?? start
            return (monthTitle(for: start), start, end)
        }

        let end = calendar.date(byAdding: .day, value: 7, to: todayStart) ?? todayStart
        return ("接下来 7 天", todayStart, end)
    }

    private func explicitMonth(in text: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: #"([0-9一二两三四五六七八九十]+)\s*月(?:份)?"#) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let monthRange = Range(match.range(at: 1), in: text),
              let month = Int(text[monthRange]) ?? chineseNumber(String(text[monthRange])),
              (1...12).contains(month)
        else {
            return nil
        }
        return month
    }

    private func relativeDayCount(in text: String) -> Int? {
        if text.contains("这几天") || text.contains("最近几天") {
            return 3
        }
        guard let regex = try? NSRegularExpression(pattern: #"(接下来|未来|最近)\s*([0-9一二两三四五六七八九十]*)\s*(天|日)"#) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        guard match.numberOfRanges > 2, let valueRange = Range(match.range(at: 2), in: text) else {
            return 7
        }
        let value = String(text[valueRange])
        let days = value.isEmpty ? 7 : (Int(value) ?? chineseNumber(value) ?? 7)
        return min(max(days, 1), 31)
    }

    private func weekendStart(from now: Date, calendar: Calendar, weekOffset: Int) -> Date {
        let weekday = calendar.component(.weekday, from: now)
        let daysUntilSaturday = (7 - weekday + 7) % 7
        let baseOffset = weekday == 1 || weekday == 7 ? 0 : daysUntilSaturday
        return calendar.date(byAdding: .day, value: baseOffset + weekOffset * 7, to: calendar.startOfDay(for: now)) ?? calendar.startOfDay(for: now)
    }

    private func answerText(
        for events: [QueryContextEvent],
        activeCount: Int,
        completedCount: Int,
        rangeTitle: String
    ) -> String {
        guard !events.isEmpty else {
            return "\(rangeTitle)暂无已记录日程。"
        }

        let lines = events.prefix(12).map { event -> String in
            let timeText = event.scheduledAt
                .flatMap { PlanDateFormatter.date(from: $0) }
                .map { PlanDateFormatter.clockText($0) } ?? "全天"
            let completedText = event.isCompleted ? "（已完成）" : ""
            return "\(displayDay(for: event)) \(timeText) \(event.title)\(completedText)"
        }
        let hiddenCount = max(events.count - lines.count, 0)
        let suffix = hiddenCount > 0 ? "\n另有 \(hiddenCount) 项未展开。" : ""
        return "\(rangeTitle)共有 \(events.count) 项日程，其中待处理 \(activeCount) 项、已完成 \(completedCount) 项。\n" + lines.joined(separator: "\n") + suffix
    }

    private func suggestions(
        for events: [QueryContextEvent],
        in text: String,
        range: (title: String, start: Date, end: Date)
    ) -> [String] {
        guard !events.isEmpty else {
            return ["这段时间暂无记录，可以安排重要事项或休息时间。"]
        }

        var suggestions: [String] = []
        if let conflict = firstConflict(in: events) {
            suggestions.append("注意 \(displayDay(for: conflict.0)) \(conflict.0.title) 和 \(conflict.1.title) 时间可能重叠。")
        }
        if let busiestDay = busiestDay(in: events), busiestDay.count >= 3 {
            suggestions.append("\(busiestDay.title) 有 \(busiestDay.count) 项待处理，是这段时间最集中的一天。")
        }
        let freeDays = freeDayCount(for: events, in: range)
        if freeDays > 0 && freeDays <= 14 {
            suggestions.append("\(range.title)还有 \(freeDays) 天没有待处理日程，可以作为机动或休息时间。")
        }
        if events.count >= 6 {
            suggestions.append("这段时间安排偏密集，建议优先确认必须完成的事项。")
        } else {
            suggestions.append("这段时间安排不算密集，可以预留机动时间。")
        }
        if text.contains("空闲") || text.contains("有空") || text.contains("忙不忙") {
            suggestions.append("全天事项不代表整天占用，具体空闲还需要结合实际持续时间判断。")
        }
        return suggestions
    }

    private func busiestDay(in events: [QueryContextEvent]) -> (title: String, count: Int)? {
        let grouped = Dictionary(grouping: events) { event in
            displayDay(for: event)
        }
        return grouped
            .map { (title: $0.key, count: $0.value.count) }
            .sorted { lhs, rhs in
                if lhs.count == rhs.count {
                    return lhs.title < rhs.title
                }
                return lhs.count > rhs.count
            }
            .first
    }

    private func freeDayCount(
        for events: [QueryContextEvent],
        in range: (title: String, start: Date, end: Date)
    ) -> Int {
        let calendar = PlanDateFormatter.zhCalendar
        let occupiedDays = Set(events.compactMap { event -> Date? in
            eventDate(for: event).map { calendar.startOfDay(for: $0) }
        })
        var cursor = calendar.startOfDay(for: range.start)
        var count = 0
        while cursor < range.end && count <= 31 {
            if !occupiedDays.contains(cursor) {
                count += 1
            }
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? range.end
        }
        return count
    }

    private func firstConflict(in events: [QueryContextEvent]) -> (QueryContextEvent, QueryContextEvent)? {
        let timedEvents = events
            .filter { !$0.isCompleted }
            .compactMap { event -> (QueryContextEvent, Date, Date)? in
                guard let start = event.scheduledAt.flatMap({ PlanDateFormatter.date(from: $0) }) else { return nil }
                let end = event.endAt.flatMap { PlanDateFormatter.date(from: $0) } ?? start.addingTimeInterval(3600)
                return (event, start, end)
            }
            .sorted { $0.1 < $1.1 }

        for index in timedEvents.indices.dropFirst() {
            let previous = timedEvents[timedEvents.index(before: index)]
            let current = timedEvents[index]
            if current.1 < previous.2 {
                return (previous.0, current.0)
            }
        }
        return nil
    }

    private func eventDate(for event: QueryContextEvent) -> Date? {
        event.scheduledAt.flatMap { PlanDateFormatter.date(from: $0) }
            ?? PlanDateFormatter.date(from: event.taskDate)
    }

    private func displayDay(for event: QueryContextEvent) -> String {
        guard let date = eventDate(for: event) else { return "未知日期" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = PlanDateFormatter.defaultTimezone
        formatter.dateFormat = "M月d日"
        return formatter.string(from: date)
    }

    private func monthTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = PlanDateFormatter.defaultTimezone
        formatter.dateFormat = "M月"
        return formatter.string(from: date)
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
        let result = text.reduce(0) { partial, character in
            partial * 10 + (values[character] ?? -100)
        }
        return result >= 0 ? result : nil
    }
}
