//
//  ContentView.swift
//  PlanAssistant7
//
//  Created by ice on 22/4/26.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        AppShellView()
    }
}

#Preview {
    ContentView()
        .modelContainer(for: SavedEvent.self, inMemory: true)
        .environment(CalendarService())
        .environment(AlarmScheduler())
        .environment(SpeechTranscriber())
        .environment(IntentParsingService())
}
