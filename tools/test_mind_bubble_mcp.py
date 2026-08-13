import hashlib
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import threading
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).with_name("mind_bubble_mcp.py")
SPEC = importlib.util.spec_from_file_location("mind_bubble_mcp", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
mcp = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(mcp)


class MindBubbleMcpJournalTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="mind-bubble-mcp-")
        self.root = Path(self.temporary.name) / "文档 with spaces" / "bubbles"
        self.journal_root = Path(self.temporary.name) / "应用支持" / "mcp-journal"
        self.service = mcp.MindBubbleService(self.root, self.journal_root)

    def tearDown(self):
        self.temporary.cleanup()

    def _create(self, operation_id="create-1"):
        result = self.service.import_bubbles(
            {
                "operationId": operation_id,
                "items": [
                    {
                        "title": "Deterministic",
                        "description": "Shared journal",
                        "appearanceFrequency": 4,
                    }
                ],
            }
        )
        ident = result["imported"][0]["id"]
        bubble = self.service.get_bubble({"id": ident})["bubble"]
        return result, bubble

    def test_paths_must_be_explicit_and_absolute(self):
        with self.assertRaisesRegex(mcp.JournalError, "MIND_BUBBLE_DIR"):
            mcp.resolve_paths({})
        with self.assertRaisesRegex(mcp.JournalError, "absolute"):
            mcp.resolve_paths(
                {
                    "MIND_BUBBLE_DIR": "relative/bubbles",
                    "MIND_BUBBLE_JOURNAL_DIR": str(self.journal_root),
                }
            )
        document_root, journal_root = mcp.resolve_paths(
            {
                "MIND_BUBBLE_DIR": str(self.root),
                "MIND_BUBBLE_JOURNAL_DIR": str(self.journal_root),
            }
        )
        self.assertTrue(document_root.is_absolute())
        self.assertTrue(journal_root.is_absolute())

    def test_crud_intents_are_isomorphic_and_reads_are_silent(self):
        _, created = self._create()
        before_reads = list((self.journal_root / "entries").glob("*.json"))

        self.service.list_bubbles({})
        self.service.search_bubbles({"query": "journal"})
        self.service.get_bubble({"id": created["id"]})
        self.assertEqual(
            len(before_reads),
            len(list((self.journal_root / "entries").glob("*.json"))),
        )

        updated = self.service.update_bubble(
            {
                "operationId": "update-1",
                "id": created["id"],
                "expectedContentHash": created["contentHash"],
                "title": "Updated",
            }
        )["bubble"]
        update_request = {
            "operationId": "update-1",
            "id": created["id"],
            "expectedContentHash": created["contentHash"],
            "title": "Updated",
        }
        self.assertEqual(
            updated,
            self.service.update_bubble(update_request)["bubble"],
        )
        delete_request = {
            "operationId": "delete-1",
            "id": created["id"],
            "expectedContentHash": updated["contentHash"],
        }
        self.service.delete_bubble(delete_request)
        self.assertEqual(
            {"deleted": created["id"]},
            self.service.delete_bubble(delete_request),
        )

        intents = self.service.journal.pending_intents()
        self.assertEqual(["create", "update", "delete"], [row["kind"] for row in intents])
        self.assertTrue(all(row["origin"] == "application" for row in intents))
        self.assertTrue(all(row["key"] == f"{created['id']}.md" for row in intents))

    def test_retry_is_idempotent_and_operation_id_reuse_conflicts(self):
        first, bubble = self._create("stable-create")
        event_count = len(list((self.journal_root / "entries").glob("*.json")))
        second, replayed_bubble = self._create("stable-create")
        self.assertEqual(first, second)
        self.assertEqual(bubble["id"], replayed_bubble["id"])
        self.assertEqual(
            event_count,
            len(list((self.journal_root / "entries").glob("*.json"))),
        )

        with self.assertRaisesRegex(mcp.JournalConflictError, "different request"):
            self.service.import_bubbles(
                {
                    "operationId": "stable-create",
                    "items": [{"title": "Different", "description": "payload"}],
                }
            )

    def test_process_exit_after_prepare_is_recovered(self):
        raw = b"journal crash recovery"
        script = f"""
import importlib.util, os
from pathlib import Path
spec = importlib.util.spec_from_file_location('mcp_child', {str(MODULE_PATH)!r})
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
journal = module.SharedJournal(Path({str(self.root)!r}), Path({str(self.journal_root)!r}))
journal.prepare_for_testing(operation_id='crash-1', object_id='bubble-crash', kind='create', expected_content_hash=None, document={raw!r}, request={{'value': 1}}, result={{'id': 'bubble-crash'}})
os._exit(91)
"""
        completed = subprocess.run([sys.executable, "-c", script], check=False)
        self.assertEqual(91, completed.returncode)
        self.assertFalse((self.root / "bubble-crash.md").exists())

        self.service.journal.recover()

        self.assertEqual(raw, (self.root / "bubble-crash.md").read_bytes())
        intents = self.service.journal.pending_intents()
        self.assertEqual(["crash-1"], [row["operationId"] for row in intents])

    def test_concurrent_same_id_has_one_winner_and_one_conflict(self):
        self.root.mkdir(parents=True)
        target = self.root / "same-id.md"
        target.write_bytes(b"base")
        expected_hash = hashlib.sha256(b"base").hexdigest()
        barrier = threading.Barrier(2)
        outcomes = []

        def mutate(operation_id, payload):
            barrier.wait()
            try:
                self.service.journal.mutate(
                    operation_id=operation_id,
                    object_id="same-id",
                    kind="update",
                    expected_content_hash=expected_hash,
                    document=payload,
                    request={"payload": payload.decode()},
                    result={"payload": payload.decode()},
                )
                outcomes.append("applied")
            except mcp.JournalConflictError:
                outcomes.append("conflict")

        threads = [
            threading.Thread(target=mutate, args=("writer-a", b"A")),
            threading.Thread(target=mutate, args=("writer-b", b"B")),
        ]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join(timeout=10)

        self.assertEqual(["applied", "conflict"], sorted(outcomes))
        self.assertIn(target.read_bytes(), {b"A", b"B"})
        self.assertEqual(1, len(self.service.journal.pending_intents()))

        winner_hash = hashlib.sha256(target.read_bytes()).hexdigest()
        self.service.journal.mutate(
            operation_id="writer-after-conflict",
            object_id="same-id",
            kind="update",
            expected_content_hash=winner_hash,
            document=b"after",
            request={"payload": "after"},
            result={"payload": "after"},
        )
        self.assertEqual(b"after", target.read_bytes())

    def test_checksum_tampering_fails_closed(self):
        self._create()
        event = next((self.journal_root / "entries").glob("*.json"))
        payload = json.loads(event.read_text(encoding="utf-8"))
        payload["operationId"] = "tampered"
        event.write_text(json.dumps(payload), encoding="utf-8")

        with self.assertRaisesRegex(mcp.JournalCorruptionError, "checksum mismatch"):
            self.service.journal.pending_intents()

    def test_normal_commit_leaves_no_temporary_files(self):
        self._create()
        leftovers = list(Path(self.temporary.name).rglob("*.mbj-tmp"))
        self.assertEqual([], leftovers)


if __name__ == "__main__":
    unittest.main()
