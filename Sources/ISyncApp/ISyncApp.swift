import AppKit
import ISyncCore
import SwiftUI

@main
struct ISyncApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra("iSync", systemImage: "arrow.triangle.2.circlepath") {
            MenuContent(model: model)
        }
        Settings {
            SettingsView(model: model)
        }
    }
}

private struct MenuContent: View {
    let model: AppModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Text(model.statusSummary)
        if let report = model.lastReport {
            ForEach(Array(report.failures.enumerated()), id: \.offset) { _, failure in
                Text(failure.description)
            }
            if report.messagesWithRawBody > 0 {
                Text("\(report.messagesWithRawBody) messages sent without decoded text")
            }
        }
        if !model.canReadMessages && model.configuration.syncMessages {
            Text("Needs Full Disk Access to read Messages")
        }
        Divider()
        Button("Sync Now") {
            Task { await model.syncNow() }
        }
        .disabled(model.isSyncing || model.configuration.apiBaseURL == nil)
        Button("Settings…") {
            NSApplication.shared.activate()
            openSettings()
        }
        .keyboardShortcut(",")
        Divider()
        Button("Quit iSync") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
