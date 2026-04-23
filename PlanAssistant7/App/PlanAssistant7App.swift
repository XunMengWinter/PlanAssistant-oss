//
//  PlanAssistant7App.swift
//  PlanAssistant7
//
//  Created by ice on 22/4/26.
//

import SwiftUI
import SwiftData

@main
struct PlanAssistant7App: App {
    @State private var calendarService = CalendarService()
    @State private var alarmScheduler = AlarmScheduler()
    @State private var speechTranscriber = SpeechTranscriber()
    @State private var parsingService = IntentParsingService()

    var body: some Scene {
        WindowGroup {
            AppShellView()
                .environment(calendarService)
                .environment(alarmScheduler)
                .environment(speechTranscriber)
                .environment(parsingService)
        }
        .modelContainer(for: SavedEvent.self)
    }
}
