"""Check local qualification containment and identity without launching UI."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    "qualify_published_ui", Path(__file__).with_name("qualify-published-ui.py"))
harness = importlib.util.module_from_spec(spec)
spec.loader.exec_module(harness)


class LocalOutputTests(unittest.TestCase):
    def test_attachment_export_uses_latest_evidence_and_ignores_escape(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            attachments = root / "attachments"
            attachments.mkdir()
            (attachments / "old.json").write_text("old")
            (attachments / "new.json").write_text("new")
            rows = [{"suggestedHumanReadableName":
                     "ui-observations_0_00000000-0000-0000-0000-000000000001.json",
                     "exportedFileName": name, "timestamp": timestamp}
                    for name, timestamp in [("old.json", 1), ("new.json", 2)]]
            rows.append({"suggestedHumanReadableName": "../escape.json",
                         "exportedFileName": "new.json", "timestamp": 3})
            (attachments / "manifest.json").write_text(json.dumps([{"attachments": rows}]))
            with patch.object(harness, "run"):
                harness.export_local_evidence(root)
            self.assertEqual((root / "ui-observations.json").read_text(), "new")
            self.assertFalse((root.parent / "escape.json").exists())

    def test_local_bundle_identity_is_stable_and_run_specific(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            identity = harness.local_candidate_identifier(root / "first")
            self.assertEqual(identity, harness.local_candidate_identifier(root / "first"))
            self.assertNotEqual(identity, harness.local_candidate_identifier(root / "second"))
            self.assertTrue(identity.startswith("com.significanthobbies.performancedaddy.qualification.r"))

    def test_owned_child_is_allowed(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            child = root / "artifacts" / "run"
            self.assertEqual(harness.validate_local_output(child, root), child)

    def test_root_and_outside_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            for path in [root / "artifacts", root / "other", root / "artifacts/../other"]:
                with self.subTest(path=path), self.assertRaises(ValueError):
                    harness.validate_local_output(path, root)

    def test_artifacts_symlink_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            (root / "outside").mkdir()
            (root / "artifacts").symlink_to(root / "outside", target_is_directory=True)
            with self.assertRaises(ValueError):
                harness.validate_local_output(root / "artifacts/run", root)

    def test_nested_escape_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            (root / "artifacts").mkdir()
            (root / "outside").mkdir()
            (root / "artifacts/escape").symlink_to(root / "outside", target_is_directory=True)
            with self.assertRaises(ValueError):
                harness.validate_local_output(root / "artifacts/escape/run", root)


if __name__ == "__main__":
    unittest.main()
