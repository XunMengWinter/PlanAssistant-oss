import Foundation

struct ScheduleIntentAPIClient {
    enum APIError: LocalizedError {
        case invalidBaseURL
        case invalidHTTPResponse
        case backend(code: String, message: String, statusCode: Int)
        case invalidResponse(String)

        var errorDescription: String? {
            switch self {
            case .invalidBaseURL:
                "后端 API 地址无效。"
            case .invalidHTTPResponse:
                "后端返回了无效 HTTP 响应。"
            case .backend(_, let message, _):
                message
            case .invalidResponse(let message):
                message
            }
        }
    }

    private let baseURL: URL
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        baseURLString: String = "https://planasstanttest-dbmejgslku.cn-hangzhou.fcapp.run",
        session: URLSession = .shared
    ) {
        self.baseURL = URL(string: baseURLString) ?? URL(fileURLWithPath: "/")
        self.session = session
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    func parseIntent(
        text: String,
        now: Date = .now,
        timezoneIdentifier: String = "Asia/Shanghai",
        locale: String = "zh_CN",
        contextEvents: [ContextEvent]
    ) async throws -> IntentResponse {
        guard baseURL.scheme?.hasPrefix("http") == true else {
            throw APIError.invalidBaseURL
        }

        let requestBody = ScheduleIntentRequest(
            text: text,
            now: PlanDateFormatter.isoString(from: now, timezoneIdentifier: timezoneIdentifier),
            timezone: timezoneIdentifier,
            locale: locale,
            context: ScheduleIntentContext(events: Array(contextEvents.prefix(20)))
        )

        let data = try await performJSONRequest(path: "/v1/schedule/intent", body: requestBody, timeout: 12)

        let intentResponse = try decoder.decode(IntentResponse.self, from: data)
        try validate(intentResponse, contextEventIDs: Set(contextEvents.map(\.id)))
        return intentResponse
    }

    func querySchedule(
        text: String,
        now: Date = .now,
        timezoneIdentifier: String = "Asia/Shanghai",
        locale: String = "zh_CN",
        contextEvents: [QueryContextEvent]
    ) async throws -> ScheduleQueryResponse {
        guard baseURL.scheme?.hasPrefix("http") == true else {
            throw APIError.invalidBaseURL
        }

        let requestBody = ScheduleQueryRequest(
            text: text,
            now: PlanDateFormatter.isoString(from: now, timezoneIdentifier: timezoneIdentifier),
            timezone: timezoneIdentifier,
            locale: locale,
            context: ScheduleQueryContext(events: Array(contextEvents.prefix(200)))
        )

        let data = try await performJSONRequest(path: "/v1/schedule/query", body: requestBody, timeout: 16)
        let queryResponse = try decoder.decode(ScheduleQueryResponse.self, from: data)
        try validate(queryResponse, contextEventIDs: Set(contextEvents.map(\.id)))
        return queryResponse
    }

    func resolveAssistant(
        text: String,
        now: Date = .now,
        timezoneIdentifier: String = "Asia/Shanghai",
        locale: String = "zh_CN",
        contextEvents: [QueryContextEvent]
    ) async throws -> AssistantResponse {
        guard baseURL.scheme?.hasPrefix("http") == true else {
            throw APIError.invalidBaseURL
        }

        let requestBody = AssistantRequest(
            text: text,
            now: PlanDateFormatter.isoString(from: now, timezoneIdentifier: timezoneIdentifier),
            timezone: timezoneIdentifier,
            locale: locale,
            context: ScheduleQueryContext(events: Array(contextEvents.prefix(200)))
        )

        let data = try await performJSONRequest(path: "/v1/schedule/assistant", body: requestBody, timeout: 20)
        let assistantResponse = try decoder.decode(AssistantResponse.self, from: data)
        try validate(
            assistantResponse,
            queryContextEventIDs: Set(contextEvents.map(\.id)),
            activeContextEventIDs: Set(contextEvents.filter { !$0.isCompleted }.map(\.id))
        )
        return assistantResponse
    }

    private func performJSONRequest<Body: Encodable>(path: String, body: Body, timeout: TimeInterval) async throws -> Data {
        let url = baseURL.appending(path: path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = timeout
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidHTTPResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if let backendError = try? decoder.decode(APIErrorResponse.self, from: data) {
                throw APIError.backend(
                    code: backendError.error.code,
                    message: backendError.error.message,
                    statusCode: httpResponse.statusCode
                )
            }
            throw APIError.backend(
                code: "http_\(httpResponse.statusCode)",
                message: "后端请求失败（HTTP \(httpResponse.statusCode)）。",
                statusCode: httpResponse.statusCode
            )
        }

        return data
    }

    private func validate(_ response: IntentResponse, contextEventIDs: Set<String>) throws {
        guard response.needsConfirmation else {
            throw APIError.invalidResponse("后端响应缺少确认流程要求。")
        }

        switch response.intent {
        case .create:
            guard response.draft != nil else {
                throw APIError.invalidResponse("创建响应缺少 draft。")
            }
            guard response.targetEventID == nil, response.candidateEventIDs.isEmpty else {
                throw APIError.invalidResponse("创建响应包含了取消目标。")
            }
        case .cancel:
            guard response.draft == nil, !response.candidateEventIDs.isEmpty else {
                throw APIError.invalidResponse("取消响应缺少候选日程。")
            }
            guard response.candidateEventIDs.allSatisfy(contextEventIDs.contains) else {
                throw APIError.invalidResponse("取消候选包含请求上下文之外的日程。")
            }
            if let targetEventID = response.targetEventID {
                guard response.candidateEventIDs.contains(targetEventID) else {
                    throw APIError.invalidResponse("取消目标不在候选列表中。")
                }
            }
        case .clarify:
            guard response.draft == nil, response.question?.isEmpty == false else {
                throw APIError.invalidResponse("澄清响应缺少 question。")
            }
        case .unsupported:
            guard response.draft == nil, response.targetEventID == nil, response.candidateEventIDs.isEmpty, response.message?.isEmpty == false else {
                throw APIError.invalidResponse("不支持响应结构无效。")
            }
        }
    }

    private func validate(_ response: ScheduleQueryResponse, contextEventIDs: Set<String>) throws {
        guard !response.title.trimmedPlanText.isEmpty else {
            throw APIError.invalidResponse("查询响应缺少 title。")
        }
        guard (0...1).contains(response.confidence) else {
            throw APIError.invalidResponse("查询响应 confidence 超出范围。")
        }
        guard response.referencedEventIDs.allSatisfy(contextEventIDs.contains) else {
            throw APIError.invalidResponse("查询响应引用了上下文之外的日程。")
        }
        if let rangeStart = response.rangeStart, PlanDateFormatter.date(from: rangeStart) == nil {
            throw APIError.invalidResponse("查询响应 rangeStart 不是有效日期。")
        }
        if let rangeEnd = response.rangeEnd, PlanDateFormatter.date(from: rangeEnd) == nil {
            throw APIError.invalidResponse("查询响应 rangeEnd 不是有效日期。")
        }

        switch response.status {
        case .answer:
            guard response.answer?.trimmedPlanText.isEmpty == false else {
                throw APIError.invalidResponse("查询回答缺少 answer。")
            }
        case .clarify:
            guard response.question?.trimmedPlanText.isEmpty == false else {
                throw APIError.invalidResponse("查询澄清响应缺少 question。")
            }
        case .unsupported:
            guard response.message?.trimmedPlanText.isEmpty == false else {
                throw APIError.invalidResponse("查询不支持响应缺少 message。")
            }
        }
    }

    private func validate(
        _ response: AssistantResponse,
        queryContextEventIDs: Set<String>,
        activeContextEventIDs: Set<String>
    ) throws {
        guard (0...1).contains(response.routeConfidence) else {
            throw APIError.invalidResponse("助理路由 confidence 超出范围。")
        }

        switch response.type {
        case .intent:
            guard let intent = response.intent, response.query == nil else {
                throw APIError.invalidResponse("助理 intent 响应结构无效。")
            }
            try validate(intent, contextEventIDs: activeContextEventIDs)
        case .query:
            guard let query = response.query, response.intent == nil else {
                throw APIError.invalidResponse("助理 query 响应结构无效。")
            }
            try validate(query, contextEventIDs: queryContextEventIDs)
        }
    }
}
