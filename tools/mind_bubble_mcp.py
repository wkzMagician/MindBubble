"""Standard MCP server for MindBubble Markdown documents.

Set MIND_BUBBLE_DIR to the app's visible ``MindBubble/bubbles`` directory.
"""

import json
import os
import sys
import time
import uuid
from pathlib import Path


ROOT = Path(
    os.environ.get(
        "MIND_BUBBLE_DIR",
        Path.home() / "Documents" / "MindBubble" / "bubbles",
    )
)


def decode_document(file: Path) -> dict:
    raw = file.read_text(encoding="utf-8").replace("\r\n", "\n")
    if not raw.startswith("---\n"):
        raise ValueError(f"{file.name}: missing JSON front matter")
    end = raw.find("\n---\n", 4)
    if end < 0:
        raise ValueError(f"{file.name}: unclosed JSON front matter")
    metadata = json.loads(raw[4:end])
    body_start = end + len("\n---\n")
    if raw.startswith("\n", body_start):
        body_start += 1
    if metadata.get("id") != file.stem:
        raise ValueError(f"{file.name}: id does not match filename")
    return {**metadata, "description": raw[body_start:]}


def encode_document(item: dict) -> str:
    metadata = {key: value for key, value in item.items() if key != "description"}
    return (
        "---\n"
        + json.dumps(metadata, ensure_ascii=False, indent=2)
        + "\n---\n\n"
        + item["description"]
    )


def write_document(item: dict) -> None:
    ROOT.mkdir(parents=True, exist_ok=True)
    target = ROOT / f"{item['id']}.md"
    temporary = target.with_suffix(".md.tmp")
    temporary.write_text(encode_document(item), encoding="utf-8")
    temporary.replace(target)


def all_items() -> list[dict]:
    if not ROOT.exists():
        return []
    return sorted(
        (decode_document(file) for file in ROOT.glob("*.md")),
        key=lambda item: int(item["updatedAt"]),
        reverse=True,
    )


def public_item(item: dict) -> dict:
    return {
        key: item[key]
        for key in (
            "id",
            "title",
            "description",
            "appearanceFrequency",
            "createdAt",
            "updatedAt",
        )
    }


def import_bubbles(args):
    rows = args.get("items", [])
    if not rows:
        raise ValueError("items must be a non-empty array")
    existing_titles = {item["title"].casefold() for item in all_items()}
    imported, skipped = [], []
    for raw in rows:
        title = str(raw.get("title", "")).strip()
        description = str(raw.get("description", "")).strip()
        if not title or not description:
            raise ValueError("title and description are required")
        if args.get("deduplicateByTitle", True) and title.casefold() in existing_titles:
            skipped.append(title)
            continue
        frequency = int(raw.get("appearanceFrequency", 3))
        if frequency not in range(1, 6):
            raise ValueError("appearanceFrequency must be 1..5")
        now = int(time.time() * 1000)
        item = {
            "schemaVersion": 2,
            "id": str(uuid.uuid4()),
            "title": title,
            "createdAt": now,
            "updatedAt": now,
            "appearanceFrequency": frequency,
            "updatedBy": "mcp",
            "shownByDevice": {},
            "description": description,
        }
        write_document(item)
        existing_titles.add(title.casefold())
        imported.append({"id": item["id"], "title": title})
    return {"imported": imported, "skipped": skipped}


def list_bubbles(args):
    limit = min(max(int(args.get("limit", 100)), 1), 500)
    return {"bubbles": [public_item(item) for item in all_items()[:limit]]}


def search_bubbles(args):
    query = str(args.get("query", "")).strip().casefold()
    if not query:
        raise ValueError("query is required")
    return {
        "bubbles": [
            public_item(item)
            for item in all_items()
            if query in item["title"].casefold()
            or query in item["description"].casefold()
        ]
    }


def get_bubble(args):
    ident = str(args.get("id", ""))
    file = ROOT / f"{ident}.md"
    if not file.exists():
        raise ValueError("Bubble not found")
    return {"bubble": public_item(decode_document(file))}


def update_bubble(args):
    ident = str(args.get("id", ""))
    file = ROOT / f"{ident}.md"
    if not file.exists():
        raise ValueError("Bubble not found")
    item = decode_document(file)
    changed = False
    for key in ("title", "description", "appearanceFrequency"):
        if key in args:
            item[key] = args[key]
            changed = True
    if not changed:
        raise ValueError("an editable field is required")
    frequency = int(item["appearanceFrequency"])
    if frequency not in range(1, 6):
        raise ValueError("appearanceFrequency must be 1..5")
    item["appearanceFrequency"] = frequency
    item["updatedAt"] = int(time.time() * 1000)
    item["updatedBy"] = "mcp"
    write_document(item)
    return {"bubble": public_item(item)}


def delete_bubble(args):
    ident = str(args.get("id", ""))
    file = ROOT / f"{ident}.md"
    if not file.exists():
        raise ValueError("Bubble not found")
    pending = ROOT.parent / ".sync" / "pending-deletes"
    pending.mkdir(parents=True, exist_ok=True)
    (pending / ident).write_text(str(int(time.time() * 1000)), encoding="utf-8")
    file.unlink()
    return {"deleted": ident}


TOOLS = [
    {
        "name": name,
        "description": description,
        "inputSchema": {"type": "object", "properties": {}},
    }
    for name, description in [
        ("import_bubbles", "Batch import concepts."),
        ("list_bubbles", "List concepts."),
        ("search_bubbles", "Search concepts."),
        ("get_bubble", "Get one concept."),
        ("update_bubble", "Update a concept."),
        ("delete_bubble", "Delete a concept."),
    ]
]
HANDLERS = {
    name: globals()[name]
    for name in [
        "import_bubbles",
        "list_bubbles",
        "search_bubbles",
        "get_bubble",
        "update_bubble",
        "delete_bubble",
    ]
}

for line in sys.stdin:
    try:
        request = json.loads(line)
        method, request_id = request.get("method"), request.get("id")
        if method == "initialize":
            result = {
                "protocolVersion": request.get("params", {}).get(
                    "protocolVersion", "2025-06-18"
                ),
                "capabilities": {"tools": {}},
                "serverInfo": {"name": "mind-bubble", "version": "2.0.0"},
            }
        elif method == "tools/list":
            result = {"tools": TOOLS}
        elif method == "tools/call":
            data = HANDLERS[request["params"]["name"]](
                request["params"].get("arguments", {})
            )
            result = {
                "content": [
                    {
                        "type": "text",
                        "text": json.dumps(data, ensure_ascii=False),
                    }
                ],
                "structuredContent": data,
                "isError": False,
            }
        else:
            result = {}
        print(
            json.dumps(
                {"jsonrpc": "2.0", "id": request_id, "result": result},
                ensure_ascii=False,
            ),
            flush=True,
        )
    except Exception as error:
        print(
            json.dumps(
                {
                    "jsonrpc": "2.0",
                    "id": request.get("id"),
                    "error": {"code": -32000, "message": str(error)},
                },
                ensure_ascii=False,
            ),
            flush=True,
        )
