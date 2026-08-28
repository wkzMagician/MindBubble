---
name: mind-bubble-import
description: Import notes from a connected note-taking source into MindBubble using stable IDs and incremental checkpoints.
---

# Mind Bubble Import

Use this skill when the user asks to bring notes from Notion, Obsidian, or another
connected note source into MindBubble. It applies to import and recurring
incremental import requests; it does not replace a source connector and must
not invent notes when no source data is available.

## Import protocol

1. Identify the connected source and use its search/list API to obtain notes.
   For an incremental run, call MindBubble's `get_import_checkpoint` MCP tool
   with the stable source ID before searching. Treat the returned cursor as an
   opaque source-specific value.
2. Convert each note into the canonical JSON batch described in
   `../../docs/MIND_BUBBLE_IMPORT_FORMAT.md`. Every item needs a stable,
   filename-safe `id`, a non-empty Markdown `title` and `description`, and an
   ISO-8601 `updatedAt` when the source provides one. Keep the same ID for the
   same source note across runs; derive a deterministic safe ID from the
   source ID and source item ID when necessary.
3. Call the MindBubble `import_bubbles` MCP tool with a unique `operationId`
   and `source: {id, cursor, nextCursor}`. Pass an empty `items` array when a
   valid incremental search found no changes, so the checkpoint can still
   advance. Do not manually edit MindBubble Markdown files or call update and
   delete tools for this import.
4. Report the imported/skipped counts and the new checkpoint. If MindBubble
   rejects a stale cursor, refresh the checkpoint and source search rather
   than forcing the batch through.

The source ID and cursor are metadata for synchronization, not note content.
Never copy source credentials or private API tokens into the import batch.
The full schema and compatibility notes are maintained in the linked document.
