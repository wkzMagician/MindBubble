# MindBubble import format

MindBubble accepts one canonical interchange format: a UTF-8 JSON file whose
top-level `format` is `mind-bubble-import` and whose `schemaVersion` is `1`.
The authoritative schema is [mind-bubble-import.schema.json](mind-bubble-import.schema.json).

```json
{
  "format": "mind-bubble-import",
  "schemaVersion": 1,
  "source": {
    "id": "notion",
    "cursor": "opaque-cursor-from-the-previous-search",
    "nextCursor": "opaque-cursor-for-the-next-search"
  },
  "items": [
    {
      "id": "notion-page-123",
      "title": "A durable idea",
      "description": "Markdown body",
      "appearanceFrequency": 3,
      "updatedAt": "2026-08-28T00:00:00Z"
    }
  ]
}
```

`items[].id` is the stable MindBubble document ID. A connector must keep it
stable for the same source note; this makes re-imports idempotent and lets an
updated note replace its previous version without creating duplicates. IDs are
deliberately restricted to safe filename characters.

For periodic imports, a connector or Agent should ask MindBubble for the last
checkpoint for the source, search the source system after that checkpoint, and
write the returned cursor into `source.cursor`. After the batch is committed,
MindBubble stores `source.nextCursor` as the checkpoint for that source. A
batch with a stale cursor is rejected, so two importers cannot silently skip or
overwrite a time window. An empty `items` array is valid when the cursor moves
forward.

MindBubble does not contain source-specific API clients. Source-specific
plugins or Agent skills should translate Notion, Obsidian, or another note
system into this format, then call the import endpoint. This keeps the app's
document model stable while allowing connectors to evolve independently.

CSV and XLSX imports remain available as a legacy compatibility path. New
connectors and manual exports should use this JSON format.
