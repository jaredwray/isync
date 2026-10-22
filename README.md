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
```

The macOS app and its build script come in a later change.

## Privacy and security

- The app reads private data. It sends that data only to the API URL that you set.
- The API URL must use HTTPS. Plain HTTP is permitted only for `localhost`.
- The client does not follow redirects, keeps no HTTP cache or cookies, and keeps the API token in
  the keychain.
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

## License

[MIT](LICENSE)
