import SwiftData
import SwiftUI

struct ConfirmEventView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(CalendarService.self) private var calendarService
    @Environment(AlarmScheduler.self) private var alarmScheduler

    let response: IntentResponse
    var onSaved: () -> Void = {}

    @State private var rawText: String
    @State private var title: String
    @State private var taskDate: Date
    @State private var scheduledAt: Date
    @State private var hasTime: Bool
    @State private var durationMinutes: Int
    @State private var reminderKind: ReminderPolicyKind
    @State private var customReminderMinutes: Int
    @State private var notes: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let kind: EventKind
    private let confidence: Double
    private let ambiguities: [String]
    private let timezoneIdentifier: String

    init(response: IntentResponse, onSaved: @escaping () -> Void = {}) {
        self.response = response
        self.onSaved = onSaved
        let draft = response.draft
        let taskDate = draft.flatMap { PlanDateFormatter.date(from: $0.taskDate) } ?? .now
        let scheduledAt = draft?.taskTime.flatMap { PlanDateFormatter.date(from: $0) } ?? taskDate
        let endAt = draft?.endAt.flatMap { PlanDateFormatter.date(from: $0) }
        let duration = endAt.map { max(Int($0.timeIntervalSince(scheduledAt) / 60), 15) } ?? 60

        _rawText = State(initialValue: draft?.rawText ?? "")
        _title = State(initialValue: draft?.title ?? "")
        _taskDate = State(initialValue: taskDate)
        _scheduledAt = State(initialValue: scheduledAt)
        _hasTime = State(initialValue: draft?.taskTime != nil)
        _durationMinutes = State(initialValue: duration)
        _reminderKind = State(initialValue: draft?.reminderPolicy.kind ?? .tenMinutesBefore)
        _customReminderMinutes = State(initialValue: draft?.reminderPolicy.offsetMinutes ?? 60)
        _notes = State(initialValue: draft?.notes ?? "")

        kind = draft?.kind ?? .calendar
        confidence = response.confidence
        ambiguities = response.ambiguities
        timezoneIdentifier = draft?.timezoneIdentifier ?? PlanDateFormatter.defaultTimezoneIdentifier
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    summaryCard
                    editableFields
                    confirmationCard
                }
                .padding(20)
                .padding(.bottom, 116)
            }
            .scrollIndicators(.hidden)
            .background(PlanStyle.appBackground.ignoresSafeArea())
            .foregroundStyle(.white)
            .overlay(alignment: .bottom) {
                floatingActionBar
            }
            .navigationTitle("AI 解析结果")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .presentationBackground(.black)
    }

    private var floatingActionBar: some View {
        VStack {
            actionButtons
                .padding(12)
                .background(PlanStyle.appBackground.opacity(0.76), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(PlanStyle.border, lineWidth: 1)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity)
        .background {
            LinearGradient(
                colors: [
                    PlanStyle.appBackground.opacity(0),
                    PlanStyle.appBackground.opacity(0.94)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("原始输入")
                .font(.caption.weight(.bold))
                .foregroundStyle(PlanStyle.textSecondary)
            Text("“\(rawText)”")
                .font(.headline)
            HStack {
                Label(kind == .alarm ? "日程 + 闹钟" : "普通日程", systemImage: kind == .alarm ? "alarm.fill" : "calendar")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(kind == .alarm ? PlanStyle.alarmOrange : PlanStyle.calendarBlue)
                Spacer()
                Text("\(Int(confidence * 100))%")
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(PlanStyle.textSecondary)
            }
        }
        .padding(16)
        .planGlassCard(cornerRadius: 20, tint: kind == .alarm ? PlanStyle.alarmOrange : PlanStyle.calendarBlue)
    }

    private var editableFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            fieldTitle("标题")
            TextField("标题", text: $title)
                .textFieldStyle(.plain)
                .font(.title3.weight(.heavy))
                .padding(12)
                .background(PlanStyle.surfaceStrong, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            fieldTitle("日期")
            DatePicker("日期", selection: $taskDate, displayedComponents: .date)
                .datePickerStyle(.compact)
                .labelsHidden()

            Toggle("包含具体时间", isOn: $hasTime)
                .font(.subheadline.weight(.bold))
                .tint(kind == .alarm ? PlanStyle.alarmOrange : PlanStyle.calendarBlue)

            if hasTime {
                fieldTitle("时间")
                DatePicker("时间", selection: $scheduledAt, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)

                if kind == .calendar {
                    Stepper("持续时间 \(durationMinutes) 分钟", value: $durationMinutes, in: 15...480, step: 15)
                        .font(.subheadline.weight(.bold))
                }
            }

            fieldTitle("提醒策略")
            Picker("提醒策略", selection: $reminderKind) {
                ForEach(ReminderPolicyKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.segmented)

            if reminderKind == .customOffset {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        TextField("提前分钟数", value: $customReminderMinutes, format: .number)
                            .keyboardType(.numberPad)
                            .textFieldStyle(.plain)
                            .padding(12)
                            .background(PlanStyle.surfaceStrong, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        Stepper("调整提前分钟数", value: $customReminderMinutes, in: 1...10080, step: 5)
                            .labelsHidden()
                    }
                    Text("当前：提前 \(customReminderDisplayText)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(PlanStyle.textSecondary)
                }
            }

            fieldTitle("备注")
            TextField("备注", text: $notes, axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(.plain)
                .padding(12)
                .background(PlanStyle.surfaceStrong, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            fieldTitle("原文调整")
            TextEditor(text: $rawText)
                .font(.subheadline.weight(.semibold))
                .scrollContentBackground(.hidden)
                .frame(height: 78)
                .padding(8)
                .background(PlanStyle.surfaceStrong, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .padding(16)
        .planGlassCard(cornerRadius: 20)
    }

    private var confirmationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("确认提示")
                .font(.caption.weight(.bold))
                .foregroundStyle(PlanStyle.textSecondary)
            Text("已按设备所在时区解析为 \(PlanDateFormatter.dateTimeText(hasTime ? combinedScheduledDate : nil))，请确认。")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
            ForEach(ambiguities, id: \.self) { ambiguity in
                Text(ambiguity)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(PlanStyle.alarmOrange)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.red)
            }
        }
        .padding(16)
        .planGlassCard(cornerRadius: 18)
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button("取消") {
                dismiss()
            }
            .buttonStyle(PlanSecondaryButtonStyle())

            Button {
                Task { await save() }
            } label: {
                Text(isSaving ? "保存中..." : (kind == .alarm ? "保存日程和闹钟" : "保存到日历"))
            }
            .buttonStyle(PlanPrimaryButtonStyle(tint: kind == .alarm ? PlanStyle.alarmOrange : PlanStyle.calendarBlue))
            .disabled(isSaving || title.trimmedPlanText.isEmpty)
        }
    }

    private var combinedScheduledDate: Date? {
        guard hasTime else { return nil }
        let calendar = PlanDateFormatter.zhCalendar
        let hour = calendar.component(.hour, from: scheduledAt)
        let minute = calendar.component(.minute, from: scheduledAt)
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: taskDate)
    }

    private var reminderPolicy: ReminderPolicy {
        ReminderPolicy(
            kind: reminderKind,
            offsetMinutes: reminderKind == .customOffset ? normalizedCustomReminderMinutes : nil
        )
    }

    private var normalizedCustomReminderMinutes: Int {
        min(max(customReminderMinutes, 1), 10080)
    }

    private var customReminderDisplayText: String {
        ReminderPolicy(kind: .customOffset, offsetMinutes: normalizedCustomReminderMinutes).displayText
            .replacingOccurrences(of: "提前 ", with: "")
    }

    private func save() async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }

        let scheduledDate = combinedScheduledDate
        let endDate = scheduledDate.flatMap { Calendar.current.date(byAdding: .minute, value: durationMinutes, to: $0) }
        let draft = DraftEvent(
            kind: kind,
            rawText: rawText.trimmedPlanText,
            title: title.trimmedPlanText,
            taskDate: PlanDateFormatter.isoString(from: PlanDateFormatter.startOfDay(for: taskDate), timezoneIdentifier: timezoneIdentifier),
            taskTime: scheduledDate.map { PlanDateFormatter.isoString(from: $0, timezoneIdentifier: timezoneIdentifier) },
            endAt: endDate.map { PlanDateFormatter.isoString(from: $0, timezoneIdentifier: timezoneIdentifier) },
            reminderPolicy: reminderPolicy,
            notes: notes.trimmedPlanText,
            timezoneIdentifier: timezoneIdentifier
        )

        guard let savedEvent = SavedEvent(draft: draft) else {
            errorMessage = "日期格式无效。"
            return
        }
        var didInsertLocalEvent = false

        do {
            let identifiers = try calendarService.saveCalendarEvent(for: savedEvent)
            savedEvent.calendarEventIdentifier = identifiers.eventIdentifier
            savedEvent.calendarExternalIdentifier = identifiers.externalIdentifier

            if kind == .alarm {
                savedEvent.alarmID = try await alarmScheduler.scheduleAlarm(for: savedEvent)
            }

            modelContext.insert(savedEvent)
            didInsertLocalEvent = true
            try modelContext.save()
            dismiss()
            onSaved()
        } catch {
            rollbackExternalResources(for: savedEvent, didInsertLocalEvent: didInsertLocalEvent)
            errorMessage = error.localizedDescription
        }
    }

    private func rollbackExternalResources(for event: SavedEvent, didInsertLocalEvent: Bool) {
        if event.kind == .alarm {
            try? alarmScheduler.cancelAlarm(identifier: event.alarmID)
        }
        try? calendarService.deleteCalendarEvent(identifier: event.calendarEventIdentifier)
        if didInsertLocalEvent {
            modelContext.delete(event)
            try? modelContext.save()
        }
    }

    private func fieldTitle(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.bold))
            .foregroundStyle(PlanStyle.textSecondary)
    }
}

struct ConfirmCancelEventView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(CalendarService.self) private var calendarService
    @Environment(AlarmScheduler.self) private var alarmScheduler

    let response: IntentResponse
    let savedEvents: [SavedEvent]

    @State private var selectedEventID: String
    @State private var isDeleting = false
    @State private var errorMessage: String?

    private var candidates: [SavedEvent] {
        savedEvents.filter { response.candidateEventIDs.contains($0.id) && !$0.isCompleted }
    }

    init(response: IntentResponse, savedEvents: [SavedEvent]) {
        self.response = response
        self.savedEvents = savedEvents
        _selectedEventID = State(initialValue: response.targetEventID ?? response.candidateEventIDs.first ?? "")
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("原始输入")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(PlanStyle.textSecondary)
                    Text("“\(response.reason ?? "确认取消")”")
                        .font(.headline)
                    Text("候选来自 App 内未完成镜像。用户点击确认前，不删除系统日历事件或 AlarmKit 闹钟。")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PlanStyle.textSecondary)
                }
                .padding(16)
                .planGlassCard(cornerRadius: 20)

                Text("选择要取消的日程")
                    .font(.headline)

                if candidates.isEmpty {
                    Text("没有可取消的候选。")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PlanStyle.textSecondary)
                } else {
                    ForEach(candidates, id: \.id) { event in
                        CandidateEventRow(event: event, isSelected: selectedEventID == event.id)
                            .onTapGesture {
                                selectedEventID = event.id
                            }
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.red)
                }

                Spacer()

                HStack(spacing: 12) {
                    Button("返回") {
                        dismiss()
                    }
                    .buttonStyle(PlanSecondaryButtonStyle())

                    Button {
                        deleteSelected()
                    } label: {
                        Text(isDeleting ? "删除中..." : "确认删除")
                    }
                    .buttonStyle(PlanPrimaryButtonStyle(tint: .red))
                    .disabled(isDeleting || selectedEventID.isEmpty)
                }
            }
            .padding(20)
            .background(PlanStyle.appBackground.ignoresSafeArea())
            .foregroundStyle(.white)
            .navigationTitle("确认取消")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationBackground(.black)
    }

    private func deleteSelected() {
        guard let event = candidates.first(where: { $0.id == selectedEventID }) else { return }
        isDeleting = true
        defer { isDeleting = false }

        do {
            try calendarService.deleteCalendarEvent(identifier: event.calendarEventIdentifier)
            if event.kind == .alarm {
                try alarmScheduler.cancelAlarm(identifier: event.alarmID)
            }
            modelContext.delete(event)
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct CandidateEventRow: View {
    var event: SavedEvent
    var isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(isSelected ? PlanStyle.calendarBlue : PlanStyle.textSecondary)
            CompactEventRow(event: event)
        }
    }
}

private struct CompactEventRow: View {
    var event: SavedEvent

    var body: some View {
        HStack(spacing: 12) {
            PlanEventKindIcon(
                kind: event.kind,
                isAllDay: event.scheduledAt == nil,
                size: 40,
                cornerRadius: 12
            )

            VStack(alignment: .leading, spacing: 5) {
                Text("\(kindLabelText) · \(PlanDateFormatter.clockText(event.scheduledAt))")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(PlanStyle.textSecondary)
                Text(event.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(event.rawText)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(PlanStyle.textMuted)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(14)
        .background(PlanStyle.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(PlanStyle.border, lineWidth: 1)
        }
    }

    private var kindLabelText: String {
        event.kind == .alarm ? "日程 + 闹钟" : event.kind.title
    }
}
