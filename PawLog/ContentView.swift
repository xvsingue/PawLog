//
//  ContentView.swift
//  PawLog
//
//  应用根视图：首页（宠物切换 + 时间线）。
//

import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        HomeView()
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(
        for: Pet.self, Record.self, WeightEntry.self, Reminder.self, Attachment.self,
        configurations: config
    )
    return ContentView()
        .modelContainer(container)
}
