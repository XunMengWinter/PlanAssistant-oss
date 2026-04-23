import SwiftUI

struct ParsingSession: Identifiable, Hashable {
    let id = UUID()
    var rawText: String
    var queryContextEvents: [QueryContextEvent]
}

struct AIParsingFlowView: View {
    @Environment(IntentParsingService.self) private var parsingService

    let session: ParsingSession
    let savedEvents: [SavedEvent]
    var onEventSaved: () -> Void = {}

    @State private var phase: AIParsingPhase = .loading

    var body: some View {
        Group {
            switch phase {
            case .loading:
                AIParsingLoadingView(rawText: session.rawText)
                    .task(id: session.id) {
                        await parse()
                    }
                    .transition(.opacity)
            case .intentResult(let response):
                resultView(for: response)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            case .queryResult(let response):
                ScheduleQueryResultView(
                    response: response,
                    referencedEvents: referencedEvents(for: response)
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(.smooth(duration: 0.32), value: phase)
        .presentationBackground(.black)
    }

    @ViewBuilder
    private func resultView(for response: IntentResponse) -> some View {
        switch response.intent {
        case .create where response.draft != nil:
            ConfirmEventView(response: response, onSaved: onEventSaved)
        case .cancel where !response.candidateEventIDs.isEmpty:
            ConfirmCancelEventView(response: response, savedEvents: savedEvents)
        case .clarify:
            ParsingMessageResultView(title: "需要补充", bodyText: response.question ?? "请补充更多日程信息。")
        case .unsupported:
            ParsingMessageResultView(title: "暂不支持", bodyText: response.message ?? "当前本地版暂不支持这个操作。")
        default:
            ParsingMessageResultView(title: "无法解析", bodyText: response.reason ?? "请换一种说法再试。")
        }
    }

    private func parse() async {
        let startedAt = Date()
        let response = await parsingService.resolve(
            text: session.rawText,
            contextEvents: session.queryContextEvents
        )
        let nextPhase: AIParsingPhase
        switch response.type {
        case .intent:
            nextPhase = .intentResult(response.intent ?? invalidAssistantIntentResponse(response))
        case .query:
            nextPhase = .queryResult(response.query ?? invalidAssistantQueryResponse(response))
        }
        let elapsed = Date().timeIntervalSince(startedAt)
        if elapsed < 0.9 {
            let remaining = UInt64((0.9 - elapsed) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: remaining)
        }
        guard !Task.isCancelled else { return }
        phase = nextPhase
    }

    private func referencedEvents(for response: ScheduleQueryResponse) -> [SavedEvent] {
        let ids = Set(response.referencedEventIDs)
        return savedEvents
            .filter { ids.contains($0.id) }
            .sorted { ($0.scheduledAt ?? $0.taskDate) < ($1.scheduledAt ?? $1.taskDate) }
    }

    private func invalidAssistantIntentResponse(_ response: AssistantResponse) -> IntentResponse {
        IntentResponse(
            intent: .unsupported,
            draft: nil,
            targetEventID: nil,
            candidateEventIDs: [],
            question: nil,
            message: "后端返回的操作结果不完整。",
            reason: response.routeReason,
            confidence: response.routeConfidence,
            ambiguities: [],
            needsConfirmation: true
        )
    }

    private func invalidAssistantQueryResponse(_ response: AssistantResponse) -> ScheduleQueryResponse {
        ScheduleQueryResponse(
            status: .unsupported,
            title: "无法回答",
            answer: nil,
            suggestions: [],
            referencedEventIDs: [],
            rangeStart: nil,
            rangeEnd: nil,
            question: nil,
            message: "后端返回的问答结果不完整。",
            confidence: response.routeConfidence,
            ambiguities: response.routeReason.map { [$0] } ?? []
        )
    }
}

private enum AIParsingPhase: Equatable {
    case loading
    case intentResult(IntentResponse)
    case queryResult(ScheduleQueryResponse)
}

private struct ParsingLoadingStep: Hashable {
    var title: String
    var subtitle: String
    var systemImage: String
}

private struct AIParsingLoadingView: View {
    @Environment(\.dismiss) private var dismiss
    var rawText: String

    @State private var isAnimating = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer(minLength: 16)

                AIParsingAnimation(isAnimating: isAnimating)
                    .frame(width: 210, height: 210)
                    .accessibilityHidden(true)

                VStack(spacing: 8) {
                    Text("AI 正在处理")
                        .font(.system(size: 30, weight: .heavy))
                    Text("正在理解请求并读取日程上下文")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PlanStyle.textSecondary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Label("原始输入", systemImage: "quote.opening")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(PlanStyle.calendarBlue)
                    Text("“\(rawText)”")
                        .font(.headline)
                        .lineLimit(3)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .planGlassCard(cornerRadius: 20, tint: PlanStyle.calendarBlue)

                VStack(spacing: 10) {
                    ForEach(loadingSteps, id: \.self) { step in
                        ParsingStepRow(title: step.title, subtitle: step.subtitle, systemImage: step.systemImage)
                    }
                }

                Spacer(minLength: 12)
            }
            .padding(20)
            .background(PlanStyle.appBackground.ignoresSafeArea())
            .foregroundStyle(.white)
            .navigationTitle("AI 解析")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("关闭")
                }
            }
            .onAppear {
                isAnimating = true
            }
        }
    }

    private var loadingSteps: [ParsingLoadingStep] {
        [
            ParsingLoadingStep(title: "语义路由", subtitle: "由后端判断操作或问答意图", systemImage: "sparkles"),
            ParsingLoadingStep(title: "上下文读取", subtitle: "读取 App 内已有日程", systemImage: "list.bullet.rectangle"),
            ParsingLoadingStep(title: "结果生成", subtitle: "生成确认页或日程回答", systemImage: "checkmark.seal")
        ]
    }
}

private struct AIParsingAnimation: View {
    var isAnimating: Bool

    var body: some View {
        ZStack {
            roundedScanner

            ForEach(0..<28, id: \.self) { index in
                Capsule()
                    .fill(PlanStyle.calendarBlue.opacity(index.isMultiple(of: 4) ? 0.9 : 0.28))
                    .frame(width: 2, height: index.isMultiple(of: 3) ? 18 : 10)
                    .offset(y: -84)
                    .rotationEffect(.degrees(Double(index) / 28 * 360))
                    .opacity(isAnimating ? 1 : 0.22)
                    .animation(
                        .easeInOut(duration: 0.8)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.035),
                        value: isAnimating
                    )
            }

            Circle()
                .trim(from: 0.06, to: 0.78)
                .stroke(
                    AngularGradient(
                        colors: [.clear, PlanStyle.calendarBlue, Color(red: 64 / 255, green: 156 / 255, blue: 1), .clear],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .frame(width: 152, height: 152)
                .rotationEffect(.degrees(isAnimating ? 360 : 0))
                .animation(.linear(duration: 1.35).repeatForever(autoreverses: false), value: isAnimating)

            Circle()
                .trim(from: 0.16, to: 0.58)
                .stroke(
                    AngularGradient(
                        colors: [.clear, PlanStyle.alarmOrange, PlanStyle.calendarBlue, .clear],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .frame(width: 112, height: 112)
                .rotationEffect(.degrees(isAnimating ? -360 : 0))
                .animation(.linear(duration: 1.9).repeatForever(autoreverses: false), value: isAnimating)

            Text("AI")
                .font(.system(size: 36, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 76, height: 76)
                .background(PlanStyle.surfaceStrong, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(PlanStyle.calendarBlue.opacity(0.55), lineWidth: 1)
                }
                .scaleEffect(isAnimating ? 1.04 : 0.96)
                .animation(.easeInOut(duration: 0.72).repeatForever(autoreverses: true), value: isAnimating)
        }
    }

    private var roundedScanner: some View {
        RoundedRectangle(cornerRadius: 34, style: .continuous)
            .stroke(PlanStyle.border, lineWidth: 1)
            .frame(width: 190, height: 190)
            .overlay {
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .stroke(PlanStyle.calendarBlue.opacity(0.18), lineWidth: 8)
                    .blur(radius: 10)
            }
            .overlay {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.clear, PlanStyle.calendarBlue.opacity(0.42), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: 52, height: 190)
                    .offset(x: isAnimating ? 96 : -96)
                    .animation(.easeInOut(duration: 1.05).repeatForever(autoreverses: true), value: isAnimating)
                    .mask(RoundedRectangle(cornerRadius: 34, style: .continuous).frame(width: 190, height: 190))
            }
    }
}

private struct ParsingStepRow: View {
    var title: String
    var subtitle: String
    var systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(PlanStyle.calendarBlue)
                .frame(width: 34, height: 34)
                .background(PlanStyle.calendarBlue.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.heavy))
                Text(subtitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PlanStyle.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer()
        }
        .padding(12)
        .background(PlanStyle.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(PlanStyle.border, lineWidth: 1)
        }
    }
}

private struct ParsingMessageResultView: View {
    @Environment(\.dismiss) private var dismiss
    var title: String
    var bodyText: String

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Spacer()
                Image(systemName: "sparkles")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(PlanStyle.calendarBlue)
                    .frame(width: 72, height: 72)
                    .background(PlanStyle.calendarBlue.opacity(0.14), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                Text(title)
                    .font(.title2.bold())
                Text(bodyText)
                    .font(.body)
                    .foregroundStyle(PlanStyle.textSecondary)
                Button("知道了") {
                    dismiss()
                }
                .buttonStyle(PlanPrimaryButtonStyle())
                Spacer()
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PlanStyle.appBackground.ignoresSafeArea())
            .foregroundStyle(.white)
            .navigationTitle("AI 解析结果")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationBackground(.black)
    }
}

private struct ScheduleQueryResultView: View {
    @Environment(\.dismiss) private var dismiss

    var response: ScheduleQueryResponse
    var referencedEvents: [SavedEvent]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    summaryCard
                    if !suggestionItems.isEmpty {
                        suggestionsCard
                    }
                    if !referencedEvents.isEmpty {
                        referencedEventsCard
                    }
                    if !response.ambiguities.isEmpty {
                        ambiguityCard
                    }
                    Button("知道了") {
                        dismiss()
                    }
                    .buttonStyle(PlanPrimaryButtonStyle())
                    .padding(.top, 4)
                }
                .padding(20)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .background(PlanStyle.appBackground.ignoresSafeArea())
            .foregroundStyle(.white)
            .navigationTitle("AI 日程问答")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("关闭")
                }
            }
        }
        .presentationBackground(.black)
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: statusIconName)
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(PlanStyle.calendarBlue)
                    .frame(width: 42, height: 42)
                    .background(PlanStyle.calendarBlue.opacity(0.14), in: RoundedRectangle(cornerRadius: 13, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(statusLabel)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(PlanStyle.textSecondary)
                    Text(response.title)
                        .font(.title3.weight(.heavy))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text(primaryText)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            HStack {
                Label("\(Int(response.confidence * 100))%", systemImage: "chart.bar.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(PlanStyle.textSecondary)
                Spacer()
                if referencedEvents.isEmpty {
                    Text("未引用日程")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(PlanStyle.textMuted)
                } else {
                    Text("引用 \(referencedEvents.count) 项")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(PlanStyle.calendarBlue)
                }
            }
        }
        .padding(16)
        .planGlassCard(cornerRadius: 20, tint: PlanStyle.calendarBlue)
    }

    private var suggestionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("建议", systemImage: "lightbulb.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(PlanStyle.alarmOrange)

            ForEach(suggestionItems, id: \.self) { suggestion in
                HStack(alignment: .top, spacing: 10) {
                    Circle()
                        .fill(PlanStyle.alarmOrange)
                        .frame(width: 6, height: 6)
                        .padding(.top, 7)
                    Text(suggestion)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16)
        .planGlassCard(cornerRadius: 20, tint: PlanStyle.alarmOrange)
    }

    private var referencedEventsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("相关日程", systemImage: "calendar")
                .font(.caption.weight(.bold))
                .foregroundStyle(PlanStyle.calendarBlue)

            ForEach(referencedEvents, id: \.id) { event in
                QueryReferencedEventRow(event: event)
            }
        }
        .padding(16)
        .planGlassCard(cornerRadius: 20)
    }

    private var ambiguityCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("提示", systemImage: "exclamationmark.triangle.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(PlanStyle.textSecondary)

            ForEach(response.ambiguities, id: \.self) { ambiguity in
                Text(ambiguity)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(PlanStyle.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .planGlassCard(cornerRadius: 18)
    }

    private var primaryText: String {
        switch response.status {
        case .answer:
            response.answer ?? "没有可展示的日程回答。"
        case .clarify:
            response.question ?? "请补充要查询的时间范围。"
        case .unsupported:
            response.message ?? "当前暂不支持这个日程问题。"
        }
    }

    private var suggestionItems: [String] {
        response.status == .answer ? response.suggestions : []
    }

    private var statusIconName: String {
        switch response.status {
        case .answer:
            "sparkles"
        case .clarify:
            "questionmark.circle.fill"
        case .unsupported:
            "nosign"
        }
    }

    private var statusLabel: String {
        switch response.status {
        case .answer:
            "AI 回复"
        case .clarify:
            "需要补充"
        case .unsupported:
            "暂不支持"
        }
    }
}

private struct QueryReferencedEventRow: View {
    var event: SavedEvent

    private var tint: Color {
        event.kind == .alarm ? PlanStyle.alarmOrange : PlanStyle.calendarBlue
    }

    var body: some View {
        HStack(spacing: 12) {
            PlanEventKindIcon(
                kind: event.kind,
                isAllDay: event.scheduledAt == nil,
                size: 38,
                cornerRadius: 12
            )

            VStack(alignment: .leading, spacing: 5) {
                Text("\(PlanDateFormatter.compactDate(event.taskDate)) · \(PlanDateFormatter.clockText(event.scheduledAt))")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(PlanStyle.textSecondary)
                Text(event.title)
                    .font(.subheadline.weight(.heavy))
                    .lineLimit(1)
                if event.isCompleted {
                    Text("已完成")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(PlanStyle.successGreen)
                }
            }
            Spacer()
        }
        .padding(12)
        .background(PlanStyle.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(tint.opacity(0.28), lineWidth: 1)
        }
    }
}
