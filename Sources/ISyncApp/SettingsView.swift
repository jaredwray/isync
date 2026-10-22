import ISyncCore
import SwiftUI

struct SettingsView: View {
    let model: AppModel

    @State private var urlText = ""
    @State private var token = ""
    @State private var interval = 15
    @State private var syncMessages = true
    @State private var syncContacts = true
    @State private var launchesAtLogin = false

    private let intervals = [5, 15, 30, 60, 120, 360, 1_440]

    var body: some View {
        Form {
            Section("Server") {
                TextField("API URL", text: $urlText, prompt: Text("https://api.example.com"))
                SecureField(
                    "API token",
                    text: $token,
                    prompt: Text(model.hasToken ? "Saved in the keychain" : "Not set")
                )
                HStack {
                    Spacer()
                    Button("Save") { save() }
                        .keyboardShortcut(.defaultAction)
                }
            }

            Section("Schedule") {
                Picker("Sync every", selection: $interval) {
                    ForEach(intervalOptions, id: \.self) { minutes in
                        Text(Self.label(minutes: minutes)).tag(minutes)
                    }
                }
                Toggle("Sync Messages", isOn: $syncMessages)
                Toggle("Sync Contacts", isOn: $syncContacts)
                Toggle("Open at login", isOn: $launchesAtLogin)
                    .onChange(of: launchesAtLogin) { _, enabled in
                        guard enabled != model.launchesAtLogin else { return }
                        model.setLaunchesAtLogin(enabled)
                        launchesAtLogin = model.launchesAtLogin
                    }
            }

            Section("Permissions") {
                PermissionRow(
                    title: "Full Disk Access (Messages)",
                    granted: model.canReadMessages,
                    action: { model.openPrivacySettings(.fullDiskAccess) }
                )
                PermissionRow(
                    title: "Contacts",
                    granted: model.canReadContacts,
                    action: {
                        Task {
                            await model.requestContactsAccess()
                            if !model.canReadContacts { model.openPrivacySettings(.contacts) }
                        }
                    }
                )
                Button("Check Again") { model.refreshStatus() }
            }

            if let error = model.settingsError {
                Section {
                    Text(error).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .onAppear(perform: load)
    }

    /// The standard intervals, plus the saved interval if a person set a different value in the file.
    private var intervalOptions: [Int] {
        intervals.contains(interval) ? intervals : (intervals + [interval]).sorted()
    }

    private func load() {
        let configuration = model.configuration
        urlText = configuration.apiBaseURL?.absoluteString ?? ""
        interval = configuration.syncIntervalMinutes
        syncMessages = configuration.syncMessages
        syncContacts = configuration.syncContacts
        model.refreshStatus()
        launchesAtLogin = model.launchesAtLogin
    }

    private func save() {
        var configuration = model.configuration
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            configuration.apiBaseURL = nil
        } else if let url = URL(string: trimmed) {
            configuration.apiBaseURL = url
        } else {
            model.settingsError = "The API URL is not a valid URL."
            return
        }
        configuration.syncIntervalMinutes = interval
        configuration.syncMessages = syncMessages
        configuration.syncContacts = syncContacts
        // Keep the token field and the error when the configuration is not valid.
        guard model.save(configuration) else { return }
        if !token.isEmpty {
            model.saveToken(token)
            token = ""
        }
    }

    private static func label(minutes: Int) -> String {
        switch minutes {
        case 60: "Hour"
        case 1_440: "Day"
        case 61...: "\(minutes / 60) hours"
        default: "\(minutes) minutes"
        }
    }
}

private struct PermissionRow: View {
    let title: String
    let granted: Bool
    let action: () -> Void

    var body: some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(granted ? .green : .orange)
            Text(title)
            Spacer()
            if !granted {
                Button("Grant…", action: action)
            }
        }
    }
}
