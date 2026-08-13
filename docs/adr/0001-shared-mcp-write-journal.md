# ADR 0001: Shared append-style journal for MCP writes

- Status: Accepted
- Date: 2026-08-14
- Scope: MindBubble Stage 7B MCP write contract

## Context

MindBubble's Flutter process and Python MCP server can both mutate the same
Markdown replica. MCP mutations are authorized user actions, so create, update,
and delete must produce the same intent shape consumed by synchronization.
Reading and listing must remain observational. A direct Python file write plus a
separate delete marker cannot guarantee that a crash will preserve both the
document mutation and its intent.

Local app/service IPC was considered, but it would make MCP availability depend
on a running Flutter process and a new authenticated transport. Stage 7B
therefore selects the plan's option 2: a shared, versioned write-ahead journal.

## Decision

Protocol version 1 is implemented by
`lib/services/shared_mcp_journal.dart` and `tools/mind_bubble_mcp.py`.

MindBubble supplies two absolute paths. `MIND_BUBBLE_DIR` is the visible
Markdown document directory. `MIND_BUBBLE_JOURNAL_DIR` is an application-support
directory outside the document directory. The MCP server has no home-directory,
Documents-directory, or repository-relative fallback. The future Flutter
integration passes the same resolved directories directly to
`SharedMcpJournal`.

The journal is an append-only directory:

```text
<journalRoot>/
  journal.lock
  entries/
    00000000000000000001-<operationHash>-prepared.json
    00000000000000000002-<operationHash>-applied.json
    00000000000000000003-<operationHash>-acknowledged.json
```

Each event contains `version`, a strictly positive unique `sequence`, `phase`,
`operationId`, and a SHA-256 `checksum`. The checksum covers canonical UTF-8 JSON
with recursively sorted object keys, compact separators, and the `checksum`
field omitted. Unknown versions, duplicate sequences/phases, malformed intent
data, and checksum mismatches fail closed.

A prepared event contains:

- the complete replacement bytes as base64, or no payload for delete;
- the expected current content SHA-256 for update/delete;
- the resulting content SHA-256 for create/update;
- a request checksum used to detect operation-ID reuse;
- an intent with `operationId`, `<id>.md` key, `create|update|delete` kind,
  `application` origin, UTC creation time, and resulting content hash;
- the stable result returned when an identical request is retried.

An applied event means the document postcondition is durable and the intent is
available to synchronization. An acknowledged event means synchronization has
consumed that intent. Read, list, search, and get never append events.

## Transaction and recovery rules

Python and Dart lock byte range 0..1 of `journal.lock` exclusively. All state
validation, recovery, precondition checks, mutation publication, and event
publication occur while holding that lock. This gives Flutter and MCP one
serialization order across processes.

Every document or event write is first flushed to a uniquely named temporary
file in the destination directory and then atomically renamed over its final
path. Temporary names end in `.mbj-tmp`; journal readers ignore them. Event files
are immutable once published.

The mutation sequence is:

1. Acquire the shared lock and validate the complete journal.
2. Recover every prepared operation lacking an applied event.
3. Append and durably publish the new prepared event.
4. Verify the current document hash equals the expected hash. Create expects no
   document. Update and delete require a caller-supplied hash from a prior read.
5. Atomically replace the document, or delete it.
6. Append and durably publish the applied event.

After termination at any boundary, the next writer or explicit startup recovery
replays the prepared payload. If the document already has the resulting hash,
recovery only appends `applied`. If it still has the expected hash, recovery
applies the payload and then appends `applied`. Any other hash is a deterministic
conflict; the journal remains unacknowledged and no competing bytes are
overwritten.

Retrying the same operation ID with the same normalized caller request returns
the prepared result without a second document mutation or intent. Reusing that
ID with a different request fails. Two updates/deletes based on the same content
hash serialize at the lock: one succeeds and the other sees a stale hash and
fails as a conflict.

Batch import uses `<batchOperationId>/<zero-based-index>` operation IDs and UUIDv5
bubble IDs. This makes a retried batch address the same operations and objects.

## Consequences

The journal intentionally stores document payloads until compaction is designed;
this is required for crash replay. It belongs in application support and is part
of the immutable backup set. Synchronization must consume only applied,
unacknowledged intents and append acknowledgement events after successful remote
commit. Compaction is not part of Stage 7B and must preserve unacknowledged or
prepared operations.

MCP update and delete calls now require `operationId` and
`expectedContentHash`. Create/import requires `operationId`. Reads return
`contentHash` so clients can form those preconditions.

The old `.sync/pending-deletes` directory is not scanned or written by this
protocol. A later migration may convert only separately verified legacy markers;
absence discovered by directory scanning is never interpreted as authorization
to delete.
