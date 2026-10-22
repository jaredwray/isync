# Sync API contract

Status: draft. The maintainer will supply the real API. When it is ready, change
`Sources/ISyncCore/API/HTTPSyncAPI.swift`, or add a different `SyncAPI` conformer. The sync
engine does not change.

## Transport

- The base URL is a setting. It must use HTTPS. Plain HTTP is permitted only for `localhost`,
  `127.0.0.1`, and `::1`.
- Each call is a `POST` with a JSON body in UTF-8. Keys are `snake_case`.
- Dates are ISO 8601 strings in UTC with milliseconds, for example `2026-10-22T21:15:03.120Z`.
- A field with no value is not in the object.
- The client does not follow redirects. A redirect is a failed request.

| Header | Value |
| --- | --- |
| `Content-Type` | `application/json` |
| `Accept` | `application/json` |
| `User-Agent` | `isync/<version>` |
| `Authorization` | `Bearer <token>`, when a token is set |
| `Idempotency-Key` | 16 hexadecimal digits. The same body always gets the same key. |

## Responses

| Status | Client action |
| --- | --- |
| 2xx | The batch is accepted. The client saves its progress. |
| 401, 403 | The run stops. The next scheduled run tries again. |
| 408, 425, 429, 5xx, or no connection | The client tries again, up to 4 attempts in total. It waits 1, 2, then 4 seconds. A `Retry-After` value in seconds replaces the wait, up to 60 seconds. |
| Other | The run stops. The next scheduled run sends the same batch again. |

The client shows the first 200 bytes of an error body in the app status. Do not put private data
in an error body.

## Delivery

- Delivery is at least once. The client sends a batch again after a failure, so the server must
  accept repeated data.
- Use `device_id` plus `guid` as the key for a message. Use `device_id` plus `id` as the key for a
  contact.
- Messages arrive in `row_id` order. The client sends the next batch only after the server
  accepts the current batch.
- The client does not send a message again after an edit or an unsend. The fields
  `date_edited` and `date_retracted` show only the state at the time of the sync.

## `POST /v1/messages`

```json
{
  "device_id": "6F1C2A2E-7C1B-4C59-9E0B-5D3B2B8F0A11",
  "messages": [
    {
      "row_id": 1042,
      "guid": "4B6E5C2D-1F0A-4E8B-9C3D-2A1B0F9E8D7C",
      "text": "See you at 6",
      "service": "iMessage",
      "is_from_me": false,
      "handle": "+15555550100",
      "date": "2026-10-22T21:15:03.120Z",
      "date_read": "2026-10-22T21:16:00.000Z",
      "item_type": 0,
      "associated_message_type": 0,
      "chat": {
        "guid": "iMessage;-;+15555550100",
        "identifier": "+15555550100",
        "service": "iMessage",
        "is_group": false,
        "participants": ["+15555550100"]
      },
      "attachments": [
        {
          "guid": "8D7C6B5A-4F3E-2D1C-0B9A-8F7E6D5C4B3A",
          "filename": "~/Library/Messages/Attachments/ab/11/photo.heic",
          "mime_type": "image/heic",
          "transfer_name": "photo.heic",
          "total_bytes": 482113
        }
      ]
    }
  ]
}
```

| Field | Description |
| --- | --- |
| `row_id` | The ROWID in chat.db. It is unique on one Mac only. |
| `guid` | The message GUID. It is the same on all devices of the person. |
| `text` | The message text. The client reads `attributedBody` when the `text` column is empty. |
| `attributed_body` | Base64 of the raw `attributedBody` bytes. The client sends it only when `text` is empty and it cannot decode the body, so the server keeps the content and can decode it later. |
| `service` | `iMessage`, `SMS`, or `RCS`. |
| `is_from_me` | True for a message that the person sent. |
| `handle` | The phone number or email address of the other person. |
| `date`, `date_read`, `date_delivered`, `date_edited`, `date_retracted` | The dates from chat.db. |
| `item_type` | 0 for a message. Other values are group events, for example a new group name. |
| `associated_message_guid`, `associated_message_type` | A tapback. Types 2000 to 2005 add a tapback. Types 3000 to 3005 remove one. |
| `thread_originator_guid` | The first message of an inline reply thread. |
| `chat` | The conversation. `participants` holds the other people. |
| `attachments` | Metadata only. The client does not upload files. |

## `POST /v1/contacts`

One call holds changed cards or deleted IDs. It does not hold both.

```json
{
  "device_id": "6F1C2A2E-7C1B-4C59-9E0B-5D3B2B8F0A11",
  "contacts": [
    {
      "id": "410FE041-5C4E-48DA-B4DE-04C15EA3DBAC:ABPerson",
      "given_name": "Ana",
      "family_name": "Lopez",
      "organization": "Example Co",
      "phones": [{ "label": "Mobile", "value": "+1 555-555-0100" }],
      "emails": [{ "label": "Work", "value": "ana@example.com" }],
      "postal_addresses": [
        { "label": "Home", "street": "1 Main St", "city": "Springfield", "postal_code": "12345", "iso_country_code": "us" }
      ],
      "birthday": "--04-12"
    }
  ],
  "deleted_contact_ids": []
}
```

| Field | Description |
| --- | --- |
| `contacts` | New and changed cards. Replace the stored card with the same `id`. |
| `deleted_contact_ids` | Cards that the Mac no longer has. Delete them. |
| `birthday` | `YYYY-MM-DD`, or `--MM-DD` when the card has no year. |
| `label` | A system label such as `Mobile` or `Home`, or a custom label from the card. |

The contact list on the server mirrors the Mac. For example, when a person turns off an account in
Contacts, the cards of that account are deleted on the server, and they come back when the person
turns the account on again. Keep deleted cards for a period on the server if you need a history.

The client does not send deletes when Contacts returns no cards. That result usually means that
the app lost access to Contacts.
