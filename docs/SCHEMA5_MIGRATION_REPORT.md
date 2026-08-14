# Dartloom schema 5 migration report

Date: 2026-08-14

## Pinned runtime

- Dartloom commit: `69ccd9e05bdaf285aad2e145e4be26dd7b246b7c`
- MindBubble configuration: schema 5
- Business data: application-owned absolute Documents path
- Replica metadata and MCP journal: application-owned absolute support paths outside the business directory
- Remote target: `/MindBubble/bubbles/`
- Legacy remote source: `/MindBubble/v2/bubbles/` (copy-only; never modified or deleted)

## Backup and migration

- Immutable backup: `C:\Users\magician\AppData\Local\DartloomBackups\mind_bubble\20260813-221650-864`
- Manifest: `C:\Users\magician\AppData\Local\DartloomBackups\mind_bubble\20260813-221650-864\manifest.json`
- The manifest, isolated restore, and all 50 live business documents were SHA-256 verified.
- `dartloom.yaml.v4.backup` preserves the schema 4 configuration.
- Legacy delete state is imported only when a marker is corroborated by the old durable `pendingDeletes` state. No scan-derived absence becomes a delete intent.
- The remote migration copies only missing Markdown objects. Existing target objects win, failures remain retryable, and the source remains unchanged.

## Compatibility and rollback

- UI writes and MCP writes share the same lock-protected, checksummed, idempotent write-ahead journal.
- External edits, deletions, and new files remain observations rather than upload/delete intent.
- Plaintext WebDAV configuration is removed only after profile and secure-secret migration succeeds.
- Roll back application integration by reverting the migration commit and restoring configuration from `dartloom.yaml.v4.backup`.
- Restore business data only into a new temporary directory, verify it against the manifest, and switch paths after verification; do not overwrite the live directory directly.

## Acceptance evidence

- Application fixtures cover baseline convergence, full local-root loss, external single-file deletion/edit/new-file behavior, explicit delete propagation, concurrent update conflicts, and partial remote listings without local or remote mutation.
- UI/repository writes and MCP writes are verified to create durable intents; successful reconciliation verifies those intents are consumed exactly once.
- Authentication mapping is covered in the MindBubble facade and WebDAV transport tests. Timeout, 429/server-limit, partial listing, and worker cleanup are covered by the pinned Dartloom package suites.
- Mid-migration retry is covered by a failed copy followed by a successful retry with the old source unchanged.
- Schema 4 dry-run blocking and applied migration backup/idempotency are covered by the pinned Dartloom CLI suite; this repository also retains its actual schema 4 backup.

## Retention decisions

- Keep the immutable local backup and schema 4 configuration backup.
- Keep the old remote directory as a read-only rollback source.
- Remove the legacy local sync-state implementation after migration; retain only its narrowly scoped import reader.
- Retain the WebDAV helper solely for the copy-only legacy remote migration. Normal synchronization is owned by Dartloom.
