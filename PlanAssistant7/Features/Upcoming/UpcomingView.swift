import EventKit
import SwiftData
import SwiftUI

struct UpcomingView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.modelContext) private var modelContext
    @Environment(CalendarService.self) private var calendarService
    @Environment(AlarmScheduler.self) private var alarmScheduler

    var savedEvents: [SavedEvent]
    @State private var errorMessage: String?
    @State private var isPastExpanded = false
    @State private var isCompletedExpanded = false

    private var sortedEvents: [SavedEvent] {
        savedEvents.sorted {
            ($0.scheduledAt ?? $0.taskDate) < ($1.scheduledAt ?? $1.taskDate)
        }
    }

    private var activeEvents: [SavedEvent] {
        sortedEvents.filter { !$0.isCompleted }
    }

    private var completedEvents: [SavedEvent] {
        sortedEvents.filter(\.isCompleted)
    }

    private var activeTodayEvents: [SavedEvent] {
        events(onOffset: 0)
    }

    private var todayEvents: [SavedEvent] {
        activeTodayEvents.filter { !isPastTodayEvent($0) }
    }

    private var pastTodayEvents: [SavedEvent] {
        activeTodayEvents.filter(isPastTodayEvent)
    }

    private var completedTodayEvents: [SavedEvent] {
        completedEvents.filter { event in
            PlanDateFormatter.zhCalendar.isDate(event.taskDate, inSameDayAs: .now)
        }
    }

    private var todayTotalCount: Int {
        todayEvents.count + pastTodayEvents.count + completedTodayEvents.count
    }

    private var tomorrowEvents: [SavedEvent] {
        events(onOffset: 1)
    }

    private var futureDateGroups: [EventDateGroup] {
        let calendar = PlanDateFormatter.zhCalendar
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: .now)) ?? .now
        let futureEvents = activeEvents.filter { event in
            !calendar.isDate(event.taskDate, inSameDayAs: .now)
                && !calendar.isDate(event.taskDate, inSameDayAs: tomorrow)
        }
        let groupedEvents = Dictionary(grouping: futureEvents) { event in
            calendar.startOfDay(for: event.taskDate)
        }

        return groupedEvents
            .map { EventDateGroup(date: $0.key, events: $0.value) }
            .sorted { $0.date < $1.date }
    }

    private var futureEventCount: Int {
        tomorrowEvents.count + futureDateGroups.reduce(0) { $0 + $1.events.count }
    }

    private var nextTodayEvent: SavedEvent? {
        todayEvents.first { event in
            guard let scheduledAt = event.scheduledAt else { return false }
            return scheduledAt >= .now
        } ?? todayEvents.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                TodayDashboard(
                    pendingCount: todayEvents.count,
                    pastCount: pastTodayEvents.count,
                    completedCount: completedTodayEvents.count
                )
                if let errorMessage {
                    ErrorBanner(message: errorMessage)
                }
                todaySection
                pastSection
                futureSections
                completedSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 18)
        }
        .scrollIndicators(.hidden)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(PlanDateFormatter.friendlyDate(.now))
                .font(.caption.weight(.bold))
                .foregroundStyle(PlanStyle.textSecondary)
            Text("今日日程")
                .font(.system(size: 32, weight: .heavy))
            Text("今天 \(todayTotalCount) 项 · 未来 \(futureEventCount) 项")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(PlanStyle.textSecondary)
            Text(nextSummaryText)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(nextTodayEvent == nil ? PlanStyle.textMuted : PlanStyle.calendarBlue)
                .lineLimit(1)
        }
    }

    private var nextSummaryText: String {
        if let nextTodayEvent {
            return "下一项 \(PlanDateFormatter.clockText(nextTodayEvent.scheduledAt)) \(nextTodayEvent.title)"
        }
        if todayTotalCount > 0 {
            return "今天暂无待处理事项"
        } else {
            return "今天暂无安排"
        }
    }

    private var todaySection: some View {
        TimelineSectionView(
            title: "今天",
            subtitle: PlanDateFormatter.weekdayText(.now),
            events: todayEvents,
            prominence: .primary,
            emptyText: todayTotalCount > 0 ? "今天暂无待处理事项" : "今天暂无安排",
            onToggle: toggleComplete,
            onOpenCalendarEvent: openCalendarEvent,
            onDelete: delete
        )
    }

    @ViewBuilder
    private var pastSection: some View {
        if !pastTodayEvents.isEmpty {
            TimelineDisclosureSection(
                title: "已过事项 \(pastTodayEvents.count) 项",
                events: pastTodayEvents,
                isExpanded: $isPastExpanded,
                maxVisibleCount: pastTodayEvents.count,
                rowOpacity: 0.72,
                onToggle: toggleComplete,
                onOpenCalendarEvent: openCalendarEvent,
                onDelete: delete
            )
        }
    }

    private var futureSections: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !tomorrowEvents.isEmpty {
                TimelineSectionView(
                    title: "明天",
                    subtitle: tomorrowSubtitle,
                    events: tomorrowEvents,
                    prominence: .secondary,
                    emptyText: nil,
                    onToggle: toggleComplete,
                    onOpenCalendarEvent: openCalendarEvent,
                    onDelete: delete
                )
            }

            ForEach(futureDateGroups) { group in
                TimelineSectionView(
                    title: monthDayText(group.date),
                    subtitle: PlanDateFormatter.weekdayText(group.date),
                    events: group.events,
                    prominence: .secondary,
                    emptyText: nil,
                    onToggle: toggleComplete,
                    onOpenCalendarEvent: openCalendarEvent,
                    onDelete: delete
                )
            }
        }
    }

    @ViewBuilder
    private var completedSection: some View {
        if !completedEvents.isEmpty {
            TimelineDisclosureSection(
                title: "已完成 \(completedEvents.count) 项",
                events: completedEvents,
                isExpanded: $isCompletedExpanded,
                maxVisibleCount: 3,
                rowOpacity: 0.58,
                onToggle: toggleComplete,
                onOpenCalendarEvent: openCalendarEvent,
                onDelete: delete
            )
        }
    }

    private var tomorrowSubtitle: String {
        let tomorrow = PlanDateFormatter.zhCalendar.date(byAdding: .day, value: 1, to: .now) ?? .now
        return PlanDateFormatter.weekdayText(tomorrow)
    }

    private func monthDayText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = PlanDateFormatter.defaultTimezone
        formatter.dateFormat = "M月d日"
        return formatter.string(from: date)
    }

    private func events(onOffset offset: Int) -> [SavedEvent] {
        let calendar = PlanDateFormatter.zhCalendar
        let target = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: .now)) ?? .now
        return activeEvents.filter { calendar.isDate($0.taskDate, inSameDayAs: target) }
    }

    private func isPastTodayEvent(_ event: SavedEvent) -> Bool {
        guard let scheduledAt = event.scheduledAt else { return false }
        return scheduledAt < .now
    }

    private func toggleComplete(_ event: SavedEvent) {
        event.isCompleted.toggle()
        event.updatedAt = .now
        try? modelContext.save()
    }

    private func openCalendarEvent(_ event: SavedEvent) {
        guard event.calendarEventIdentifier != nil else {
            errorMessage = "未找到对应的系统日历事件。"
            return
        }

        let targetDate = calendarService.calendarEvent(identifier: event.calendarEventIdentifier)?.startDate
            ?? event.scheduledAt
            ?? event.taskDate
        guard let url = URL(string: "calshow:\(targetDate.timeIntervalSinceReferenceDate)") else {
            errorMessage = "无法打开系统日历。"
            return
        }
        openURL(url)
    }

    private func delete(_ event: SavedEvent) {
        do {
            try calendarService.deleteCalendarEvent(identifier: event.calendarEventIdentifier)
            if event.kind == .alarm {
                try alarmScheduler.cancelAlarm(identifier: event.alarmID)
            }
            modelContext.delete(event)
            try modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ErrorBanner: View {
    var message: String

    var body: some View {
        Text(message)
            .font(.caption.weight(.bold))
            .foregroundStyle(PlanStyle.alertRed)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PlanStyle.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct TodayDashboard: View {
    var pendingCount: Int
    var pastCount: Int
    var completedCount: Int

    var body: some View {
        HStack(spacing: 10) {
            DashboardMetric(
                title: "待处理",
                value: pendingCount,
                systemImage: "clock",
                tint: PlanStyle.calendarBlue
            )
            DashboardMetric(
                title: "完成",
                value: completedCount,
                systemImage: "checkmark.circle.fill",
                tint: PlanStyle.successGreen
            )
            DashboardMetric(
                title: "已过",
                value: pastCount,
                systemImage: "clock.badge.exclamationmark",
                tint: PlanStyle.alertRed
            )
        }
    }
}

private struct DashboardMetric: View {
    var title: String
    var value: Int
    var systemImage: String
    var tint: Color

    var body: some View {
        HStack(alignment: .center, spacing: 9) {
            VStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(tint)
                    .frame(width: 18, height: 18)
                Text(title)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(PlanStyle.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
            }
            Text("\(value)")
                .font(.title2.weight(.heavy))
                .foregroundStyle(.white)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .frame(maxWidth: .infinity, minHeight: 68, alignment: .center)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .planGlassCard(cornerRadius: 16, tint: tint)
    }
}

private struct EventDateGroup: Identifiable {
    var date: Date
    var events: [SavedEvent]

    var id: Date { date }
}

private enum TimelineSectionProminence {
    case primary
    case secondary
}

private struct TimelineSectionView: View {
    var title: String
    var subtitle: String
    var events: [SavedEvent]
    var prominence: TimelineSectionProminence
    var emptyText: String?
    var onToggle: (SavedEvent) -> Void
    var onOpenCalendarEvent: (SavedEvent) -> Void
    var onDelete: (SavedEvent) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: prominence == .primary ? 12 : 10) {
            HStack(spacing: 8) {
                Text(title)
                    .font(prominence == .primary ? .title3.weight(.heavy) : .headline.weight(.heavy))
                Text(subtitle)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(PlanStyle.textSecondary)
                Text("\(events.count) 项")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(PlanStyle.textSecondary)
                Spacer()
            }

            if events.isEmpty {
                if let emptyText {
                    Text(emptyText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PlanStyle.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 12)
                }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                        TimelineEventRow(
                            event: event,
                            density: prominence == .primary ? .regular : .compact,
                            isLast: index == events.count - 1,
                            onToggle: onToggle,
                            onOpenCalendarEvent: onOpenCalendarEvent,
                            onDelete: onDelete
                        )
                    }
                }
            }
        }
    }
}

private enum TimelineEventRowDensity {
    case regular
    case compact
}

private struct TimelineEventRow: View {
    var event: SavedEvent
    var density: TimelineEventRowDensity
    var isLast: Bool
    var onToggle: (SavedEvent) -> Void
    var onOpenCalendarEvent: (SavedEvent) -> Void
    var onDelete: (SavedEvent) -> Void

    private var tint: Color {
        event.kind == .alarm ? PlanStyle.alarmOrange : PlanStyle.calendarBlue
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            timelineRail

            HStack(alignment: .center, spacing: 12) {
                Button {
                    onToggle(event)
                } label: {
                    Image(systemName: event.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(event.isCompleted ? PlanStyle.successGreen : PlanStyle.textSecondary)
                        .frame(width: 30, height: 36)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(event.isCompleted ? "标记为未完成" : "标记为完成")

                Button {
                    onOpenCalendarEvent(event)
                } label: {
                    PlanEventKindIcon(
                        kind: event.kind,
                        isAllDay: event.scheduledAt == nil,
                        size: 34,
                        cornerRadius: 10
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("打开系统日历日程")

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 7) {
                        Text(kindLabelText)
                            .font(.caption2.weight(.heavy))
                            .foregroundStyle(tint)
                        if let noteText {
                            Text(noteText)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(PlanStyle.textSecondary)
                                .lineLimit(1)
                        }
                    }

                    Text(event.title)
                        .font(.subheadline.weight(.heavy))
                        .lineLimit(density == .regular ? 2 : 1)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button(role: .destructive) {
                    onDelete(event)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(PlanStyle.textMuted)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("删除日程")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, density == .regular ? 13 : 11)
            .planGlassCard(cornerRadius: 18, interactive: true, tint: tint)
        }
        .padding(.bottom, isLast ? 0 : 10)
    }

    private var timelineRail: some View {
        VStack(spacing: 5) {
            Text(PlanDateFormatter.clockText(event.scheduledAt))
                .font(.caption.weight(.heavy))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .frame(width: 48, alignment: .trailing)

            Circle()
                .fill(tint)
                .frame(width: 7, height: 7)

            if !isLast {
                Rectangle()
                    .fill(PlanStyle.border.opacity(0.82))
                    .frame(width: 1, height: density == .regular ? 54 : 44)
            }
        }
        .frame(width: 48)
        .padding(.top, 2)
    }

    private var kindLabelText: String {
        event.kind == .alarm ? "日程 + 闹钟" : event.kind.title
    }

    private var noteText: String? {
        let trimmedNotes = event.notes.trimmedPlanText
        return trimmedNotes.isEmpty ? nil : trimmedNotes
    }
}

private struct TimelineDisclosureSection: View {
    var title: String
    var events: [SavedEvent]
    @Binding var isExpanded: Bool
    var maxVisibleCount: Int
    var rowOpacity: Double
    var onToggle: (SavedEvent) -> Void
    var onOpenCalendarEvent: (SavedEvent) -> Void
    var onDelete: (SavedEvent) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.smooth(duration: 0.22)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Text(title)
                        .font(.subheadline.weight(.heavy))
                        .foregroundStyle(PlanStyle.textSecondary)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(PlanStyle.textMuted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    let visibleEvents = Array(events.prefix(maxVisibleCount))
                    ForEach(Array(visibleEvents.enumerated()), id: \.element.id) { index, event in
                        TimelineEventRow(
                            event: event,
                            density: .compact,
                            isLast: index == visibleEvents.count - 1,
                            onToggle: onToggle,
                            onOpenCalendarEvent: onOpenCalendarEvent,
                            onDelete: onDelete
                        )
                        .opacity(rowOpacity)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}
