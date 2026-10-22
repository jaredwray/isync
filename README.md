# isync

isync is a native macOS menu bar app. It sends your iMessages and your Contacts to an API that you
control, on a schedule.

> Status: early. The API layer is a draft. See [docs/API.md](docs/API.md).

## What it does

- Reads new messages from the Messages database (`~/Library/Messages/chat.db`) in read-only mode.
- Reads the cards in the Contacts app and finds new, changed, and deleted cards.
- Sends the changes to your API over HTTPS in batches, every 5 minutes to once a day.
- Saves its progress only after the API accepts a batch, so a failure does not lose data.

The sync sends message text, message metadata, and attachment metadata. It does not upload
attachment files.

## Requirements

- macOS 14 (Sonoma) or later.
- Full Disk Access for the app, to read the Messages database.
- Access to Contacts, if you sync Contacts.
- An API that accepts the requests in [docs/API.md](docs/API.md).

## Build and run

```sh
swift build
swift test
scripts/build-app.sh
open build/iSync.app
```

`scripts/build-app.sh` builds `build/iSync.app` and signs it with the hardened runtime. The default
signature is ad-hoc. macOS keeps privacy permissions for each signature, so an ad-hoc build asks for
the permissions again after each build. To keep them, set a stable identity:

```sh
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" scripts/build-app.sh
```

## Set up

1. Open iSync. An icon appears in the menu bar.
2. Open **Settings…** from the menu.
3. Enter the API URL and the API token, then click **Save**. The token goes to the keychain.
4. Under **Permissions**, click **Grant…** for Full Disk Access. In System Settings, add iSync and
   turn it on. Messages data is not available to the app without this permission.
5. Click **Grant…** for Contacts, then allow access.
6. Select the sync interval, and turn on **Open at login**.

The app syncs when it starts, then on the schedule. Use **Sync Now** for an immediate sync.

### Command-line tool

`isync-cli` uses the same settings, state, and keychain item as the app.

```sh
swift run isync-cli status
swift run isync-cli sync --dry-run   # Reads the data and prints counts. Sends and saves nothing.
swift run isync-cli sync
```

The terminal app needs Full Disk Access to read Messages. The command-line tool cannot ask for
access to Contacts, so it skips Contacts when it has no access. Use the iSync app to sync Contacts.
Set `ISYNC_API_TOKEN` to use a token that is not in the keychain.

## Privacy and security

- The app reads private data. It sends that data only to the API URL that you set.
- The API URL must use HTTPS. Plain HTTP is permitted only for `localhost`.
- The client does not follow redirects, keeps no HTTP cache or cookies, and keeps the API token in
  the keychain.
- When you change the API server, the app removes the old token, so it does not go to the new server.
  When you change the API URL, the next sync sends all data again.
- The app and `isync-cli` do not sync at the same time. A lock file stops a second sync.
- The settings and the sync state are in `~/Library/Application Support/isync/`. Only your user can
  read them. They hold no message text.
- The app log holds counts and errors only. It does not hold message text or contact details.
- The package has no third-party dependencies.

See [SECURITY.md](SECURITY.md) to report a vulnerability.

## Design

- [ADR-0001](docs/adr/0001-sync-architecture.md) explains the architecture.
- `Sources/ISyncCore` has the sync logic: the Messages reader, the Contacts diff, the HTTP client,
  the state store, and the sync engine. It has no Apple-only frameworks, so its tests also run on
  Linux.
- `Sources/ISyncMac` has the macOS adapters: Contacts, the keychain, the login item, and the
  background scheduler.
- `Sources/ISyncApp` is the menu bar app. `Sources/isync-cli` is the command-line tool.

## License

[MIT](LICENSE)
