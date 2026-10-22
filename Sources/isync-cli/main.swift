import Foundation
import ISyncCore
import ISyncMac

/// A command-line front end for tests and support. The menu bar app is the main way to run the sync.
let usage = """
    Usage: isync-cli <command>

    Commands:
      sync [--dry-run]  Run one sync now. --dry-run reads the data and prints counts.
                        It sends nothing and saves nothing.
      status            Print the settings, the permissions, and the sync state.
      help              Print this help.

    The API token comes from the ISYNC_API_TOKEN environment variable, or from the keychain.
    """

/// Accepts each upload and sends nothing. A dry run uses it in place of the HTTP API.
struct DryRunAPI: SyncAPI {
    func upload(messages: [Message], deviceID: String) async throws {}
    func upload(contacts: [Contact], deletedContactIDs: [String], deviceID: String) async throws {}
}

func printReport(_ report: SyncReport, dryRun: Bool) {
    let verb = dryRun ? "would send" : "sent"
    print("Messages \(verb): \(report.messagesUploaded)")
    print("Contacts \(verb): \(report.contactsUploaded) changed, \(report.contactsDeleted) deleted")
    for failure in report.failures {
        print("Failed: \(failure)")
    }
}

func runSync(dryRun: Bool) async -> Int32 {
    do {
        let configuration = try ConfigurationStore().load()
        if configuration.syncContacts && !SystemContactSource.isAuthorized {
            // macOS asks the person once. The terminal app then gets the Contacts permission.
            _ = try? await SystemContactSource.requestAccess()
        }
        let token = try ProcessInfo.processInfo.environment["ISYNC_API_TOKEN"] ?? KeychainTokenStore().read()
        let engine: SyncEngine
        if dryRun {
            let saved = try FileSyncStateStore().loadIfPresent() ?? SyncState()
            engine = try SyncService.makeEngine(
                configuration: configuration,
                token: token,
                api: DryRunAPI(),
                stateStore: InMemorySyncStateStore(saved)
            )
        } else {
            engine = try SyncService.makeEngine(configuration: configuration, token: token)
        }
        let report = await engine.run()
        printReport(report, dryRun: dryRun)
        return report.succeeded ? 0 : 1
    } catch {
        print("Failed: \(error)")
        return 1
    }
}

func printStatus() -> Int32 {
    do {
        let configuration = try ConfigurationStore().load()
        let state = try FileSyncStateStore().loadIfPresent()
        print("API URL: \(configuration.apiBaseURL?.absoluteString ?? "not set")")
        print("Interval: \(configuration.syncIntervalMinutes) minutes")
        print("Messages: \(configuration.syncMessages ? "on" : "off"), readable: \(SyncService.canReadMessages())")
        print("Contacts: \(configuration.syncContacts ? "on" : "off"), authorized: \(SystemContactSource.isAuthorized)")
        print("Message cursor: \(state.map { String($0.messageCursor) } ?? "none")")
        print("Synced contacts: \(state?.contactHashes.count ?? 0)")
        return 0
    } catch {
        print("Failed: \(error)")
        return 1
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())
let status: Int32
switch arguments.first {
case "sync":
    let options = Set(arguments.dropFirst())
    guard options.isSubset(of: ["--dry-run"]) else {
        print(usage)
        exit(64)
    }
    status = await runSync(dryRun: options.contains("--dry-run"))
case "status":
    status = printStatus()
case "help", "--help", "-h":
    print(usage)
    status = 0
default:
    print(usage)
    status = 64
}
exit(status)
