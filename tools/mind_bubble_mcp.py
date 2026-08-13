"""MCP server for MindBubble Markdown documents.

MindBubble must supply absolute document and journal paths through
``MIND_BUBBLE_DIR`` and ``MIND_BUBBLE_JOURNAL_DIR``. Mutations are committed
through the version 1 shared journal before they are reported as successful.
"""

from __future__ import annotations

import base64
import contextlib
import hashlib
import json
import os
import re
import sys
import tempfile
import time
import uuid
from pathlib import Path
from typing import Mapping


PROTOCOL_VERSION = 1
DOCUMENT_ROOT_ENV = "MIND_BUBBLE_DIR"
JOURNAL_ROOT_ENV = "MIND_BUBBLE_JOURNAL_DIR"
_ID_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$")
_OPERATION_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:/-]{0,199}$")


class JournalError(RuntimeError):
    """Base class for shared-journal failures."""


class JournalConflictError(JournalError):
    """Raised when an operation precondition or operation ID conflicts."""


class JournalCorruptionError(JournalError):
    """Raised when a journal event is invalid or has a bad checksum."""


def _canonical_json(value: object) -> str:
    return json.dumps(
        value,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    )


def _sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def _checksum_event(event: Mapping[str, object]) -> str:
    unsigned = {key: value for key, value in event.items() if key != "checksum"}
    return _sha256_bytes(_canonical_json(unsigned).encode("utf-8"))


def _require_absolute_path(environment: Mapping[str, str], name: str) -> Path:
    raw = environment.get(name, "").strip()
    if not raw:
        raise JournalError(f"{name} must be supplied by MindBubble")
    value = Path(raw)
    if not value.is_absolute():
        raise JournalError(f"{name} must be an absolute path")
    return value.resolve(strict=False)


def resolve_paths(environment: Mapping[str, str] | None = None) -> tuple[Path, Path]:
    values = os.environ if environment is None else environment
    document_root = _require_absolute_path(values, DOCUMENT_ROOT_ENV)
    journal_root = _require_absolute_path(values, JOURNAL_ROOT_ENV)
    try:
        journal_root.relative_to(document_root)
    except ValueError:
        pass
    else:
        raise JournalError("journal directory must be outside the document directory")
    return document_root, journal_root


def _validate_id(value: object) -> str:
    ident = str(value or "")
    if not _ID_PATTERN.fullmatch(ident):
        raise ValueError("id must contain only letters, numbers, '_' or '-'")
    return ident


def _validate_operation_id(value: object) -> str:
    operation_id = str(value or "")
    if not _OPERATION_PATTERN.fullmatch(operation_id):
        raise ValueError(
            "operationId is required and must be 1..200 safe ASCII characters"
        )
    return operation_id


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


def public_item(item: dict, *, content_hash: str | None = None) -> dict:
    result = {
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
    if content_hash is not None:
        result["contentHash"] = content_hash
    return result


class _CrossProcessLock:
    """The byte 0..1 lock shared by the Dart and Python implementations."""

    def __init__(self, path: Path):
        self.path = path
        self._file = None

    def __enter__(self):
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self._file = self.path.open("a+b")
        self._file.seek(0, os.SEEK_END)
        if self._file.tell() == 0:
            self._file.write(b"\0")
            self._file.flush()
            os.fsync(self._file.fileno())
        self._file.seek(0)
        if os.name == "nt":
            import msvcrt

            while True:
                try:
                    msvcrt.locking(self._file.fileno(), msvcrt.LK_LOCK, 1)
                    break
                except OSError:
                    time.sleep(0.01)
        else:
            import fcntl

            fcntl.lockf(self._file.fileno(), fcntl.LOCK_EX, 1, 0, os.SEEK_SET)
        return self

    def __exit__(self, exc_type, exc, traceback):
        assert self._file is not None
        self._file.seek(0)
        if os.name == "nt":
            import msvcrt

            msvcrt.locking(self._file.fileno(), msvcrt.LK_UNLCK, 1)
        else:
            import fcntl

            fcntl.lockf(self._file.fileno(), fcntl.LOCK_UN, 1, 0, os.SEEK_SET)
        self._file.close()
        self._file = None


class SharedJournal:
    """Versioned append-style write-ahead journal shared with Flutter."""

    def __init__(self, document_root: Path, journal_root: Path):
        self.document_root = document_root.resolve(strict=False)
        self.journal_root = journal_root.resolve(strict=False)
        try:
            self.journal_root.relative_to(self.document_root)
        except ValueError:
            pass
        else:
            raise JournalError("journal directory must be outside document directory")
        self.entries_root = self.journal_root / "entries"
        self.lock_path = self.journal_root / "journal.lock"

    def mutate(
        self,
        *,
        operation_id: str,
        object_id: str,
        kind: str,
        expected_content_hash: str | None,
        document: bytes | None,
        request: object,
        result: object,
    ) -> dict:
        operation_id = _validate_operation_id(operation_id)
        object_id = _validate_id(object_id)
        if kind not in {"create", "update", "delete"}:
            raise ValueError("kind must be create, update or delete")
        if kind == "create" and expected_content_hash is not None:
            raise ValueError("create must not have an expectedContentHash")
        if kind in {"update", "delete"} and not expected_content_hash:
            raise ValueError(f"{kind} requires expectedContentHash")
        if kind == "delete" and document is not None:
            raise ValueError("delete must not contain document bytes")
        if kind != "delete" and document is None:
            raise ValueError(f"{kind} requires document bytes")

        content_hash = None if document is None else _sha256_bytes(document)
        payload_base64 = None if document is None else base64.b64encode(document).decode()
        request_checksum = _sha256_bytes(
            _canonical_json(
                {
                    "version": PROTOCOL_VERSION,
                    "operationId": operation_id,
                    "objectId": object_id,
                    "kind": kind,
                    "expectedContentHash": expected_content_hash,
                    "request": request,
                }
            ).encode("utf-8")
        )

        with _CrossProcessLock(self.lock_path):
            state = self._load_state()
            self._recover_locked(state)
            existing = state.get(operation_id)
            if existing is not None:
                prepared = existing["prepared"]
                if prepared["requestChecksum"] != request_checksum:
                    raise JournalConflictError(
                        "operationId was already used for a different request"
                    )
                return {
                    "operationId": operation_id,
                    "replayed": True,
                    "result": prepared["result"],
                }

            target = self.document_root / f"{object_id}.md"
            current_hash = (
                _sha256_bytes(target.read_bytes()) if target.exists() else None
            )
            if current_hash != expected_content_hash:
                raise JournalConflictError(
                    f"{operation_id}: expected {expected_content_hash!r}, "
                    f"found {current_hash!r}"
                )

            prepared = {
                "version": PROTOCOL_VERSION,
                "sequence": self._next_sequence(state),
                "phase": "prepared",
                "operationId": operation_id,
                "requestChecksum": request_checksum,
                "expectedContentHash": expected_content_hash,
                "payloadBase64": payload_base64,
                "result": result,
                "intent": {
                    "operationId": operation_id,
                    "key": f"{object_id}.md",
                    "kind": kind,
                    "origin": "application",
                    "createdAt": self._utc_now(),
                    "contentHash": content_hash,
                },
            }
            self._append_event(prepared)
            state[operation_id] = {"prepared": prepared}
            self._recover_operation_locked(state, operation_id)
            return {"operationId": operation_id, "replayed": False, "result": result}

    def recover(self) -> None:
        with _CrossProcessLock(self.lock_path):
            self._recover_locked(self._load_state())

    def pending_intents(self) -> list[dict]:
        with _CrossProcessLock(self.lock_path):
            state = self._load_state()
            self._recover_locked(state)
            return [
                entry["prepared"]["intent"]
                for entry in state.values()
                if "applied" in entry and "acknowledged" not in entry
            ]

    def acknowledge(self, operation_id: str) -> None:
        operation_id = _validate_operation_id(operation_id)
        with _CrossProcessLock(self.lock_path):
            state = self._load_state()
            self._recover_locked(state)
            entry = state.get(operation_id)
            if entry is None or "applied" not in entry:
                raise JournalConflictError("cannot acknowledge an unapplied operation")
            if "acknowledged" in entry:
                return
            event = {
                "version": PROTOCOL_VERSION,
                "sequence": self._next_sequence(state),
                "phase": "acknowledged",
                "operationId": operation_id,
            }
            self._append_event(event)

    def operation(self, operation_id: str) -> dict | None:
        operation_id = _validate_operation_id(operation_id)
        with _CrossProcessLock(self.lock_path):
            state = self._load_state()
            self._recover_locked(state)
            entry = state.get(operation_id)
            if entry is None or "applied" not in entry:
                return None
            return entry["prepared"]

    def replay_result(
        self,
        *,
        operation_id: str,
        object_id: str,
        kind: str,
        expected_content_hash: str | None,
        request: object,
    ) -> object | None:
        operation_id = _validate_operation_id(operation_id)
        object_id = _validate_id(object_id)
        request_checksum = _sha256_bytes(
            _canonical_json(
                {
                    "version": PROTOCOL_VERSION,
                    "operationId": operation_id,
                    "objectId": object_id,
                    "kind": kind,
                    "expectedContentHash": expected_content_hash,
                    "request": request,
                }
            ).encode("utf-8")
        )
        with _CrossProcessLock(self.lock_path):
            state = self._load_state()
            self._recover_locked(state)
            entry = state.get(operation_id)
            if entry is None or "applied" not in entry:
                return None
            prepared = entry["prepared"]
            if prepared["requestChecksum"] != request_checksum:
                raise JournalConflictError(
                    "operationId was already used for a different request"
                )
            return prepared["result"]

    def prepare_for_testing(
        self,
        *,
        operation_id: str,
        object_id: str,
        kind: str,
        expected_content_hash: str | None,
        document: bytes | None,
        request: object,
        result: object,
    ) -> None:
        """Write only the WAL prepare event to simulate process termination."""
        operation_id = _validate_operation_id(operation_id)
        object_id = _validate_id(object_id)
        content_hash = None if document is None else _sha256_bytes(document)
        payload_base64 = None if document is None else base64.b64encode(document).decode()
        request_checksum = _sha256_bytes(
            _canonical_json(
                {
                    "version": PROTOCOL_VERSION,
                    "operationId": operation_id,
                    "objectId": object_id,
                    "kind": kind,
                    "expectedContentHash": expected_content_hash,
                    "request": request,
                }
            ).encode("utf-8")
        )
        with _CrossProcessLock(self.lock_path):
            state = self._load_state()
            event = {
                "version": PROTOCOL_VERSION,
                "sequence": self._next_sequence(state),
                "phase": "prepared",
                "operationId": operation_id,
                "requestChecksum": request_checksum,
                "expectedContentHash": expected_content_hash,
                "payloadBase64": payload_base64,
                "result": result,
                "intent": {
                    "operationId": operation_id,
                    "key": f"{object_id}.md",
                    "kind": kind,
                    "origin": "application",
                    "createdAt": self._utc_now(),
                    "contentHash": content_hash,
                },
            }
            self._append_event(event)

    def _recover_locked(self, state: dict[str, dict]) -> None:
        for operation_id, entry in list(state.items()):
            if "applied" not in entry:
                self._recover_operation_locked(state, operation_id)

    def _recover_operation_locked(self, state: dict[str, dict], operation_id: str) -> None:
        entry = state[operation_id]
        prepared = entry["prepared"]
        intent = prepared["intent"]
        target = self.document_root / intent["key"]
        current_hash = _sha256_bytes(target.read_bytes()) if target.exists() else None
        expected_hash = prepared["expectedContentHash"]
        result_hash = intent["contentHash"]
        kind = intent["kind"]

        already_applied = current_hash == result_hash if kind != "delete" else current_hash is None
        if not already_applied:
            if current_hash != expected_hash:
                raise JournalConflictError(
                    f"{operation_id}: expected {expected_hash!r}, found {current_hash!r}"
                )
            if kind == "delete":
                target.unlink()
                self._sync_directory(target.parent)
            else:
                payload = base64.b64decode(prepared["payloadBase64"], validate=True)
                if _sha256_bytes(payload) != result_hash:
                    raise JournalCorruptionError(
                        f"{operation_id}: payload checksum does not match intent"
                    )
                self._atomic_write(target, payload)

        event = {
            "version": PROTOCOL_VERSION,
            "sequence": self._next_sequence(state),
            "phase": "applied",
            "operationId": operation_id,
            "resultContentHash": result_hash,
        }
        self._append_event(event)
        entry["applied"] = event

    def _load_state(self) -> dict[str, dict]:
        state: dict[str, dict] = {}
        sequences: set[int] = set()
        if not self.entries_root.exists():
            return state
        for file in sorted(self.entries_root.glob("*.json")):
            try:
                event = json.loads(file.read_text(encoding="utf-8"))
            except (OSError, UnicodeError, json.JSONDecodeError) as error:
                raise JournalCorruptionError(f"invalid journal event {file.name}") from error
            if not isinstance(event, dict) or event.get("version") != PROTOCOL_VERSION:
                raise JournalCorruptionError(f"unsupported journal event {file.name}")
            if event.get("checksum") != _checksum_event(event):
                raise JournalCorruptionError(f"checksum mismatch in {file.name}")
            sequence = event.get("sequence")
            if not isinstance(sequence, int) or sequence <= 0 or sequence in sequences:
                raise JournalCorruptionError(f"invalid sequence in {file.name}")
            sequences.add(sequence)
            operation_id = _validate_operation_id(event.get("operationId"))
            phase = event.get("phase")
            entry = state.setdefault(operation_id, {})
            if phase == "prepared":
                if entry:
                    raise JournalCorruptionError(f"duplicate prepare for {operation_id}")
                self._validate_prepared(event)
                entry["prepared"] = event
            elif phase == "applied":
                if "prepared" not in entry or "applied" in entry:
                    raise JournalCorruptionError(f"invalid applied event for {operation_id}")
                entry["applied"] = event
            elif phase == "acknowledged":
                if "applied" not in entry or "acknowledged" in entry:
                    raise JournalCorruptionError(
                        f"invalid acknowledged event for {operation_id}"
                    )
                entry["acknowledged"] = event
            else:
                raise JournalCorruptionError(f"unknown journal phase in {file.name}")
        return state

    def _validate_prepared(self, event: dict) -> None:
        intent = event.get("intent")
        if not isinstance(intent, dict):
            raise JournalCorruptionError("prepared event has no intent")
        operation_id = event["operationId"]
        if intent.get("operationId") != operation_id or intent.get("origin") != "application":
            raise JournalCorruptionError(f"invalid intent for {operation_id}")
        key = intent.get("key")
        if not isinstance(key, str) or not key.endswith(".md"):
            raise JournalCorruptionError(f"invalid intent key for {operation_id}")
        _validate_id(key[:-3])
        if intent.get("kind") not in {"create", "update", "delete"}:
            raise JournalCorruptionError(f"invalid intent kind for {operation_id}")
        if not isinstance(event.get("requestChecksum"), str):
            raise JournalCorruptionError(f"invalid request checksum for {operation_id}")

    def _next_sequence(self, state: dict[str, dict]) -> int:
        return 1 + max(
            (
                phase["sequence"]
                for entry in state.values()
                for phase in entry.values()
                if isinstance(phase, dict) and "sequence" in phase
            ),
            default=0,
        )

    def _append_event(self, event: dict) -> None:
        self.entries_root.mkdir(parents=True, exist_ok=True)
        signed = {**event, "checksum": _checksum_event(event)}
        operation_hash = _sha256_bytes(event["operationId"].encode("utf-8"))[:16]
        name = f"{event['sequence']:020d}-{operation_hash}-{event['phase']}.json"
        target = self.entries_root / name
        if target.exists():
            raise JournalCorruptionError(f"journal event already exists: {name}")
        self._atomic_write(target, (_canonical_json(signed) + "\n").encode("utf-8"))

    def _atomic_write(self, target: Path, payload: bytes) -> None:
        target.parent.mkdir(parents=True, exist_ok=True)
        descriptor, temporary_name = tempfile.mkstemp(
            prefix=f".{target.name}.", suffix=".mbj-tmp", dir=target.parent
        )
        temporary = Path(temporary_name)
        try:
            with os.fdopen(descriptor, "wb") as output:
                output.write(payload)
                output.flush()
                os.fsync(output.fileno())
            os.replace(temporary, target)
            self._sync_directory(target.parent)
        finally:
            with contextlib.suppress(FileNotFoundError):
                temporary.unlink()

    @staticmethod
    def _sync_directory(directory: Path) -> None:
        if os.name == "nt" or not hasattr(os, "O_DIRECTORY"):
            return
        descriptor = os.open(directory, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(descriptor)
        finally:
            os.close(descriptor)

    @staticmethod
    def _utc_now() -> str:
        return time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime()) + "Z"


class MindBubbleService:
    def __init__(self, document_root: Path, journal_root: Path):
        self.root = document_root.resolve(strict=False)
        self.journal = SharedJournal(self.root, journal_root)

    def all_items(self) -> list[dict]:
        if not self.root.exists():
            return []
        return sorted(
            (decode_document(file) for file in self.root.glob("*.md")),
            key=lambda item: int(item["updatedAt"]),
            reverse=True,
        )

    def public_items(self) -> list[dict]:
        if not self.root.exists():
            return []
        rows = []
        for file in self.root.glob("*.md"):
            raw = file.read_bytes()
            rows.append(
                public_item(decode_document(file), content_hash=_sha256_bytes(raw))
            )
        return sorted(rows, key=lambda item: int(item["updatedAt"]), reverse=True)

    def import_bubbles(self, args):
        batch_operation_id = _validate_operation_id(args.get("operationId"))
        if len(batch_operation_id) > 180:
            raise ValueError("batch operationId must be at most 180 characters")
        rows = args.get("items", [])
        if not rows:
            raise ValueError("items must be a non-empty array")
        existing_titles = {item["title"].casefold() for item in self.all_items()}
        imported, skipped = [], []
        for index, raw in enumerate(rows):
            operation_id = f"{batch_operation_id}/{index}"
            title = str(raw.get("title", "")).strip()
            description = str(raw.get("description", "")).strip()
            if not title or not description:
                raise ValueError("title and description are required")
            frequency = int(raw.get("appearanceFrequency", 3))
            if frequency not in range(1, 6):
                raise ValueError("appearanceFrequency must be 1..5")
            existing = self.journal.operation(operation_id)
            if (
                existing is None
                and args.get("deduplicateByTitle", True)
                and title.casefold() in existing_titles
            ):
                skipped.append(title)
                continue
            now = int(time.time() * 1000)
            ident = str(uuid.uuid5(uuid.NAMESPACE_URL, f"mindbubble:{operation_id}"))
            item = {
                "schemaVersion": 2,
                "id": ident,
                "title": title,
                "createdAt": now,
                "updatedAt": now,
                "appearanceFrequency": frequency,
                "updatedBy": "mcp",
                "shownByDevice": {},
                "description": description,
            }
            encoded = encode_document(item).encode("utf-8")
            result = public_item(item, content_hash=_sha256_bytes(encoded))
            transaction = self.journal.mutate(
                operation_id=operation_id,
                object_id=ident,
                kind="create",
                expected_content_hash=None,
                document=encoded,
                request={
                    "title": title,
                    "description": description,
                    "appearanceFrequency": frequency,
                },
                result=result,
            )
            stored = transaction["result"]
            existing_titles.add(stored["title"].casefold())
            imported.append({"id": stored["id"], "title": stored["title"]})
        return {"imported": imported, "skipped": skipped}

    def list_bubbles(self, args):
        limit = min(max(int(args.get("limit", 100)), 1), 500)
        return {"bubbles": self.public_items()[:limit]}

    def search_bubbles(self, args):
        query = str(args.get("query", "")).strip().casefold()
        if not query:
            raise ValueError("query is required")
        return {
            "bubbles": [
                item
                for item in self.public_items()
                if query in item["title"].casefold()
                or query in item["description"].casefold()
            ]
        }

    def get_bubble(self, args):
        ident = _validate_id(args.get("id"))
        file = self.root / f"{ident}.md"
        if not file.exists():
            raise ValueError("Bubble not found")
        raw = file.read_bytes()
        return {
            "bubble": public_item(
                decode_document(file), content_hash=_sha256_bytes(raw)
            )
        }

    def update_bubble(self, args):
        operation_id = _validate_operation_id(args.get("operationId"))
        ident = _validate_id(args.get("id"))
        expected_hash = str(args.get("expectedContentHash", ""))
        if not expected_hash:
            raise ValueError("expectedContentHash is required")
        request = {
            key: args[key]
            for key in ("title", "description", "appearanceFrequency")
            if key in args
        }
        if not request:
            raise ValueError("an editable field is required")
        if "appearanceFrequency" in request:
            frequency = int(request["appearanceFrequency"])
            if frequency not in range(1, 6):
                raise ValueError("appearanceFrequency must be 1..5")
            request["appearanceFrequency"] = frequency
        file = self.root / f"{ident}.md"
        if not file.exists():
            prior = self.journal.replay_result(
                operation_id=operation_id,
                object_id=ident,
                kind="update",
                expected_content_hash=expected_hash,
                request=request,
            )
            if prior is not None:
                return {"bubble": prior}
            raise ValueError("Bubble not found")
        item = decode_document(file)
        item.update(request)
        frequency = int(item["appearanceFrequency"])
        if frequency not in range(1, 6):
            raise ValueError("appearanceFrequency must be 1..5")
        item["appearanceFrequency"] = frequency
        item["updatedAt"] = int(time.time() * 1000)
        item["updatedBy"] = "mcp"
        encoded = encode_document(item).encode("utf-8")
        result = public_item(item, content_hash=_sha256_bytes(encoded))
        transaction = self.journal.mutate(
            operation_id=operation_id,
            object_id=ident,
            kind="update",
            expected_content_hash=expected_hash,
            document=encoded,
            request=request,
            result=result,
        )
        return {"bubble": transaction["result"]}

    def delete_bubble(self, args):
        operation_id = _validate_operation_id(args.get("operationId"))
        ident = _validate_id(args.get("id"))
        expected_hash = str(args.get("expectedContentHash", ""))
        if not expected_hash:
            raise ValueError("expectedContentHash is required")
        transaction = self.journal.mutate(
            operation_id=operation_id,
            object_id=ident,
            kind="delete",
            expected_content_hash=expected_hash,
            document=None,
            request={"id": ident},
            result={"deleted": ident},
        )
        return transaction["result"]


def _tool(name: str, description: str, properties: dict, required: list[str] | None = None):
    schema = {"type": "object", "properties": properties}
    if required:
        schema["required"] = required
    return {"name": name, "description": description, "inputSchema": schema}


TOOLS = [
    _tool(
        "import_bubbles",
        "Batch import concepts as authorized create intents.",
        {
            "operationId": {"type": "string", "maxLength": 180},
            "items": {"type": "array", "minItems": 1, "items": {"type": "object"}},
            "deduplicateByTitle": {"type": "boolean"},
        },
        ["operationId", "items"],
    ),
    _tool("list_bubbles", "List concepts without creating intents.", {"limit": {"type": "integer"}}),
    _tool("search_bubbles", "Search concepts without creating intents.", {"query": {"type": "string"}}, ["query"]),
    _tool("get_bubble", "Get one concept without creating intents.", {"id": {"type": "string"}}, ["id"]),
    _tool(
        "update_bubble",
        "Update a concept using an optimistic hash precondition.",
        {
            "operationId": {"type": "string"},
            "id": {"type": "string"},
            "expectedContentHash": {"type": "string"},
            "title": {"type": "string"},
            "description": {"type": "string"},
            "appearanceFrequency": {"type": "integer", "minimum": 1, "maximum": 5},
        },
        ["operationId", "id", "expectedContentHash"],
    ),
    _tool(
        "delete_bubble",
        "Delete a concept using an optimistic hash precondition.",
        {
            "operationId": {"type": "string"},
            "id": {"type": "string"},
            "expectedContentHash": {"type": "string"},
        },
        ["operationId", "id", "expectedContentHash"],
    ),
]


def serve(service: MindBubbleService, input_stream=sys.stdin, output_stream=sys.stdout):
    handlers = {
        "import_bubbles": service.import_bubbles,
        "list_bubbles": service.list_bubbles,
        "search_bubbles": service.search_bubbles,
        "get_bubble": service.get_bubble,
        "update_bubble": service.update_bubble,
        "delete_bubble": service.delete_bubble,
    }
    for line in input_stream:
        request = {}
        try:
            request = json.loads(line)
            method, request_id = request.get("method"), request.get("id")
            if method == "initialize":
                result = {
                    "protocolVersion": request.get("params", {}).get(
                        "protocolVersion", "2025-06-18"
                    ),
                    "capabilities": {"tools": {}},
                    "serverInfo": {"name": "mind-bubble", "version": "3.0.0"},
                }
            elif method == "tools/list":
                result = {"tools": TOOLS}
            elif method == "tools/call":
                data = handlers[request["params"]["name"]](
                    request["params"].get("arguments", {})
                )
                result = {
                    "content": [
                        {"type": "text", "text": json.dumps(data, ensure_ascii=False)}
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
                file=output_stream,
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
                file=output_stream,
                flush=True,
            )


def main() -> None:
    document_root, journal_root = resolve_paths()
    service = MindBubbleService(document_root, journal_root)
    service.journal.recover()
    serve(service)


if __name__ == "__main__":
    main()
