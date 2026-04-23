import EventKit
import SwiftData
import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case capture
    case upcoming

    var id: String { rawValue }

    var title: String {
        switch self {
        case .capture:
            "录入"
        case .upcoming:
            "今日"
        }
    }

    var systemImage: String {
        switch self {
        case .capture:
            "mic.fill"
        case .upcoming:
            "calendar"
        }
    }
}

enum AppSheet: Identifiable {
    case parsing(ParsingSession)
    case create(IntentResponse)
    case cancel(IntentResponse)
    case message(title: String, body: String)

    var id: String {
        switch self {
        case .parsing(let session):
            "parsing-\(session.id.uuidString)"
        case .create(let response):
            "create-\(response.draft?.rawText ?? UUID().uuidString)"
        case .cancel(let response):
            "cancel-\(response.candidateEventIDs.joined(separator: "-"))-\(response.reason ?? "")"
        case .message(let title, let body):
            "message-\(title)-\(body)"
        }
    }
}

struct AppShellView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(CalendarService.self) private var calendarService
    @Environment(AlarmScheduler.self) private var alarmScheduler
    @Environment(SpeechTranscriber.self) private var speechTranscriber

    @Query(sort: \SavedEvent.taskDate) private var savedEvents: [SavedEvent]
    @State private var selectedTab: AppTab = .capture
    @State private var presentedSheet: AppSheet?

    var body: some View {
        TabView(selection: $selectedTab) {
            CaptureView(
                onParseRequest: { rawText in
                    startParsing(rawText)
                }
            )
            .background(PlanStyle.appBackground.ignoresSafeArea())
            .tabItem {
                Label(AppTab.capture.title, systemImage: AppTab.capture.systemImage)
            }
            .tag(AppTab.capture)

            UpcomingView(savedEvents: savedEvents)
                .background(PlanStyle.appBackground.ignoresSafeArea())
                .tabItem {
                    Label(AppTab.upcoming.title, systemImage: AppTab.upcoming.systemImage)
                }
                .tag(AppTab.upcoming)
        }
        .tint(PlanStyle.calendarBlue)
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .parsing(let session):
                AIParsingFlowView(
                    session: session,
                    savedEvents: savedEvents,
                    onEventSaved: showToday
                )
            case .create(let response):
                ConfirmEventView(response: response, onSaved: showToday)
            case .cancel(let response):
                ConfirmCancelEventView(response: response, savedEvents: savedEvents)
            case .message(let title, let body):
                MessageSheet(title: title, bodyText: body)
                    .presentationDetents([.height(260)])
            }
        }
        .task {
            await calendarService.requestAccessOnLaunch()
            await alarmScheduler.requestAccessOnLaunch()
            await speechTranscriber.requestPermissionsOnLaunch()
        }
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in
            removeExternallyDeletedCalendarEvents()
        }
    }

    private func startParsing(_ rawText: String) {
        let text = rawText.trimmedPlanText
        let queryContextEvents = savedEvents
            .sorted { ($0.scheduledAt ?? $0.taskDate) < ($1.scheduledAt ?? $1.taskDate) }
            .map(\.queryContextEvent)
        presentedSheet = .parsing(
            ParsingSession(
                rawText: text,
                queryContextEvents: queryContextEvents
            )
        )
    }

    private func showToday() {
        selectedTab = .upcoming
    }

    private func present(_ response: IntentResponse) {
        switch response.intent {
        case .create where response.draft != nil:
            presentedSheet = .create(response)
        case .cancel where !response.candidateEventIDs.isEmpty:
            presentedSheet = .cancel(response)
        case .clarify:
            presentedSheet = .message(title: "需要补充", body: response.question ?? "请补充更多日程信息。")
        case .unsupported:
            presentedSheet = .message(title: "暂不支持", body: response.message ?? "当前本地版暂不支持这个操作。")
        default:
            presentedSheet = .message(title: "无法解析", body: response.reason ?? "请换一种说法再试。")
        }
    }

    private func removeExternallyDeletedCalendarEvents() {
        let missingIDs = calendarService.locallyMissingCalendarEventIDs(from: savedEvents)
        guard !missingIDs.isEmpty else { return }
        for event in savedEvents where missingIDs.contains(event.id) {
            if event.kind == .alarm {
                try? alarmScheduler.cancelAlarm(identifier: event.alarmID)
            }
            modelContext.delete(event)
        }
        try? modelContext.save()
    }
}

private struct MessageSheet: View {
    @Environment(\.dismiss) private var dismiss
    var title: String
    var bodyText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title)
                .font(.title2.bold())
            Text(bodyText)
                .font(.body)
                .foregroundStyle(.secondary)
            Button("知道了") {
                dismiss()
            }
            .buttonStyle(PlanPrimaryButtonStyle())
        }
        .padding(24)
        .presentationBackground(.black)
    }
}
