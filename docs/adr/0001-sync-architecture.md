# ADR-0001: Read local data stores and push changes from a menu bar app

**Status:** Accepted
**Date:** 2026-10-22
**Deciders:** Jared Wray
**Reversibility:** Two-way door

## Context

isync must send the iMessages and Contacts of one Mac to an API on a schedule. The API does not
exist yet. Apple supplies no public API to read iMessages. The data is private, so the design must
keep the attack surface small and must not lose or duplicate data silently.

## Decision drivers

1. The data stays private: few dependencies, HTTPS only, no secrets on disk.
2. No lost data after a crash, a failed request, or a sleep.
3. The API can change without a change to the sync logic.
4. Small, testable code for one maintainer.

## Options considered

### Messages source

- **A: Read `~/Library/Messages/chat.db` read-only with SQLite.** This is the only complete source.
  It needs Full Disk Access. The schema is private and changes between macOS versions.
- **B: Script Messages.app with AppleScript.** It cannot read history, and Apple removes features
  from the dictionary.

### Change tracking

- **Messages:** a cursor on `message.ROWID`. The table uses AUTOINCREMENT, so new rows always get a
  higher ROWID. The cursor moves only after the API accepts a batch.
- **Contacts:** fetch all cards and compare a content hash of each card with the hash from the last
  sync. `CNChangeHistoryFetchRequest` is the alternative, but it is hard to use from Swift and it
  loses history when the store resets.

### Schedule

- **A: A menu bar app with `NSBackgroundActivityScheduler`.** One process holds the permissions. The
  system picks a good time in the tolerance window. `SMAppService` opens the app at login.
- **B: A LaunchAgent that starts a command-line tool.** Full Disk Access and Contacts then apply to
  a second binary, and a person has no place to see the status.

## Decision

We will use option A for each choice. A read-only SQLite connection to chat.db gives the complete
history. A ROWID cursor and Contacts hashes give at-least-once delivery, which the API handles by
GUID. A menu bar app gives one place for permissions, settings, and status.

The core logic is in `ISyncCore`. It has no Apple-only frameworks, so its tests also run on Linux.
`SyncAPI`, `MessageSource`, and `ContactSource` are protocols. The real API will need a change to
`HTTPSyncAPI` only.

## Consequences

**What changes:**
- The app needs Full Disk Access for Messages and the Contacts permission.
- A new macOS version can change the chat.db schema. The reader selects NULL for optional columns
  that are missing, and CI runs on the latest macOS runner.

**Now explicitly out of scope:**
- Attachment files. The sync sends attachment metadata only.
- Edits and unsends after a message synced. A later version can track `date_edited`.
- Sync from the server back to the Mac.

**What we accept:**
- If a person restores an older chat.db with a higher ROWID than the cursor, the sync skips the
  rows below the cursor. If the new database has a lower ROWID than the cursor, the sync sends all
  messages again.
- The content hash is FNV-1a. It finds changes. It is not a security control.
