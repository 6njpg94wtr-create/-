"""Offline regression checks for actual source integrity and import invariants."""
import copy
import gzip
import hashlib
import importlib.util
import json
import sqlite3
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]


def load_script(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / "Scripts" / (name+".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


builder = load_script("build_dictionary")
validator = load_script("validate_dictionary")


def teaching_entry(identifier="editorial:mama", russian="мама", stressed="ма́ма", tier=1):
    # Synthetic unit-test fixtures, never included in the bundled dictionary.
    return {"id": identifier, "russian": russian, "stressed": stressed, "chinese": "妈妈",
            "part_of_speech": "noun", "source": "unit-test fixture", "license": "CC0-1.0",
            "reviewed_by": "test fixture", "reviewed_at": "2026-01-01", "review_reference": "fixture-only",
            "review_status": "verified", "tier": tier}


class TeachingPackTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)

    def tearDown(self):
        self.temp.cleanup()

    def apply(self, records, base=None):
        pack = self.root / "pack.json"
        pack.write_text(json.dumps({"schema_version": 1, "entries": records}, ensure_ascii=False))
        return builder.apply_teaching_pack(base or [], pack)

    def test_duplicate_teaching_id_rejected(self):
        record = teaching_entry()
        with self.assertRaisesRegex(ValueError, "Duplicate teaching ID"):
            self.apply([record, copy.deepcopy(record)])

    def test_duplicate_lemma_with_different_id_rejected(self):
        with self.assertRaisesRegex(ValueError, "Duplicate lemma/POS"):
            self.apply([teaching_entry(), teaching_entry(identifier="second-id")])

    def test_empty_or_non_chinese_definition_rejected(self):
        for value in ["", "   ", "mother"]:
            with self.subTest(value=value), self.assertRaises(ValueError):
                self.apply([{**teaching_entry(), "chinese": value}])

    def test_invalid_tier_rejected(self):
        for value in [0, 3, 4, True, "1"]:
            with self.subTest(value=value), self.assertRaises(ValueError):
                self.apply([{**teaching_entry(), "tier": value}])

    def test_missing_or_unsupported_license_rejected(self):
        for value in ["", "proprietary", "unknown"]:
            with self.subTest(value=value), self.assertRaises(ValueError):
                self.apply([{**teaching_entry(), "license": value}])

    def test_review_evidence_required(self):
        for field in ["reviewed_by", "reviewed_at", "review_reference", "source"]:
            record = teaching_entry()
            record.pop(field)
            with self.subTest(field=field), self.assertRaises(ValueError):
                self.apply([record])
        with self.assertRaises(ValueError):
            self.apply([{**teaching_entry(), "review_status": "pending"}])

    def test_missing_or_unrelated_stress_rejected(self):
        for stressed in ["", "мама", "па́па"]:
            with self.subTest(stressed=stressed), self.assertRaises(ValueError):
                self.apply([{**teaching_entry(), "stressed": stressed}])

    def test_yo_display_preserved_and_search_equivalent(self):
        self.assertEqual(builder.unicode_stress("ёлка"), "ёлка")
        self.assertEqual(builder.unicode_stress("берёза"), "берёза")
        self.assertEqual(builder.unicode_stress("ма'ма"), "ма́ма")
        self.assertEqual(builder.search_key("ёлка"), builder.search_key("елка"))
        self.assertEqual(builder.search_key("ма́ма"), builder.search_key("мама"))
        self.assertNotEqual(builder.search_key("май"), builder.search_key("маи"))

    def test_core_is_included_in_foundation_not_added_twice(self):
        entries, _ = self.apply([teaching_entry(), teaching_entry(identifier="editorial:papa", russian="папа", stressed="па́па", tier=2)])
        core = {row["id"] for row in entries if row["tier"] == 1}
        foundation = {row["id"] for row in entries if row["tier"] in (1, 2)}
        self.assertEqual(len(core), 1)
        self.assertEqual(len(foundation), 2)
        self.assertTrue(core.issubset(foundation))

    def test_core_target_limit_is_enforced(self):
        base = [{"id": f"fixture:{index}", "russian": f"тест{index}", "part_of_speech": "noun", "tier": 1} for index in range(1001)]
        with self.assertRaisesRegex(ValueError, "exceed"):
            self.apply([], base)


class DictionaryImportTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.source = self.root / "source"
        self.source.mkdir()
        self.manifest = {"repository": "https://example.invalid/unit-test-source", "commit": "fixture", "license": "CC-BY-SA-4.0", "files": {}}
        for filename in builder.TABLES:
            data = "bare\taccented\ttranslations_en\n"
            if filename == "nouns.csv":
                data += "мама\tма'ма\tmother\nмама\tма'ма\tmom\nёлка\tёлка\tfir tree\nпусто\tпу'сто\t\n"
            raw = data.encode()
            compressed = gzip.compress(raw, mtime=0)
            (self.source / (filename+".gz")).write_bytes(compressed)
            self.manifest["files"][filename] = {"url": "https://example.invalid/"+filename, "sha256": hashlib.sha256(raw).hexdigest(), "gzip_sha256": hashlib.sha256(compressed).hexdigest(), "raw_bytes": len(raw)}
        (self.source / "manifest.json").write_text(json.dumps(self.manifest))

    def tearDown(self):
        self.temp.cleanup()

    def test_checksum_rejects_modified_source(self):
        path = self.source / "nouns.csv.gz"
        path.write_bytes(gzip.compress(b"tampered source", mtime=0))
        with patch.object(builder, "SOURCE", self.source), self.assertRaisesRegex(ValueError, "checksum mismatch"):
            builder.source_bytes("nouns.csv", self.manifest)

    def test_import_merges_senses_excludes_missing_definition_and_marks_pending(self):
        destination = self.root / "test.sqlite"
        with patch.object(builder, "SOURCE", self.source):
            result = builder.build(destination)
        self.assertEqual(result["entries"], 2)
        self.assertEqual(result["duplicate_source_rows_merged"], 1)
        self.assertEqual(result["missing_english_rows_excluded"], 1)
        with sqlite3.connect(destination) as connection:
            row = connection.execute("SELECT english,tier,review_status,chinese FROM entries WHERE russian='мама'").fetchone()
            self.assertEqual(row, ("mother | mom", 3, "pending", ""))
            self.assertEqual(connection.execute("SELECT stressed FROM entries WHERE russian='ёлка'").fetchone()[0], "ёлка")

    def test_failed_teaching_import_keeps_existing_database_bytes(self):
        destination = self.root / "existing.sqlite"
        with patch.object(builder, "SOURCE", self.source):
            builder.build(destination)
            before = destination.read_bytes()
            pack = self.root / "bad.json"
            pack.write_text(json.dumps({"schema_version": 1, "entries": [{**teaching_entry(), "chinese": ""}]}))
            with self.assertRaises(ValueError):
                builder.build(destination, teaching_pack=pack)
            self.assertEqual(destination.read_bytes(), before)

    def test_source_failure_keeps_existing_database_bytes(self):
        destination = self.root / "existing.sqlite"
        with patch.object(builder, "SOURCE", self.source):
            builder.build(destination)
            before = destination.read_bytes()
            (self.source / "verbs.csv.gz").write_bytes(b"not gzip")
            with self.assertRaises((OSError, EOFError)):
                builder.build(destination)
            self.assertEqual(destination.read_bytes(), before)


class BundledDictionaryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.database = ROOT / "Resources/dictionary.sqlite"
        if not cls.database.is_file():
            raise unittest.SkipTest("Bundled dictionary unavailable; run Scripts/build_dictionary.py")

    def test_all_pinned_source_checksums_match(self):
        records = validator.inspect_sources(ROOT / "Data/openrussian")
        self.assertEqual(len(records), 4)
        for record in records:
            with self.subTest(source=record["name"]):
                self.assertTrue(record["raw_sha256_matches"])
                self.assertTrue(record["gzip_sha256_matches"])
                self.assertTrue(record["raw_size_matches"])

    def test_real_dictionary_has_30000_queries_without_invented_teaching_content(self):
        with sqlite3.connect(self.database.resolve().as_uri()+"?mode=ro", uri=True) as connection:
            count = connection.execute("SELECT count(*) FROM entries").fetchone()[0]
            self.assertGreaterEqual(count, 30000)
            self.assertEqual(connection.execute("SELECT count(*) FROM entries WHERE tier IN (1,2) AND (chinese='' OR review_status!='verified')").fetchone()[0], 0)
            self.assertEqual(connection.execute("SELECT count(*) FROM entries WHERE source='' OR license=''").fetchone()[0], 0)
            self.assertEqual(connection.execute("PRAGMA integrity_check").fetchone()[0], "ok")

    def test_inflection_finds_real_lemma_and_uses_index(self):
        with sqlite3.connect(self.database.resolve().as_uri()+"?mode=ro", uri=True) as connection:
            rows = connection.execute("SELECT russian FROM entries WHERE id IN (SELECT entry_id FROM forms WHERE form_key=?)", ("мамы",)).fetchall()
            self.assertIn(("мама",), rows)
            plan = connection.execute("EXPLAIN QUERY PLAN SELECT entry_id FROM forms WHERE form_key=?", ("мамы",)).fetchall()
            self.assertTrue(any("SEARCH" in item[3] for item in plan), plan)


if __name__ == "__main__":
    unittest.main()
