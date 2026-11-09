#!/usr/bin/env python3
"""Build the offline lookup dictionary from a pinned, checksummed CC BY-SA source.

No translation, stress placement, frequency or pedagogical review is invented.
Source TSVs are stored as reproducible gzip files, so ordinary builds are offline.
"""
from __future__ import annotations

import argparse
import csv
import gzip
import hashlib
import io
import json
import re
import sqlite3
import tempfile
import unicodedata
import urllib.request
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "Data/openrussian"
DATABASE = ROOT / "Resources/dictionary.sqlite"
ACCENT = "\u0301"
VOWELS = "аеёиоуыэюяАЕЁИОУЫЭЮЯ"
TABLES = {"nouns.csv": "noun", "verbs.csv": "verb", "adjectives.csv": "adjective", "others.csv": "other"}
NON_FORMS = {"bare", "accented", "translations_en", "translations_de", "gender", "aspect", "partner", "animate", "indeclinable", "sg_only", "pl_only"}


def search_key(text: str) -> str:
    """Ignore acute stress and ё/e; preserve й and all other meaningful letters."""
    decomposed = unicodedata.normalize("NFD", text).replace(ACCENT, "")
    return unicodedata.normalize("NFC", decomposed).casefold().replace("ё", "е").strip()


def unicode_stress(text: str) -> str:
    # Upstream places an apostrophe immediately after the stressed vowel.
    return unicodedata.normalize("NFC", re.sub("([" + VOWELS + "])'", lambda match: match[1] + ACCENT, text))


def source_bytes(filename: str, manifest: dict, download: bool = False) -> bytes:
    record = manifest["files"][filename]
    path = SOURCE / (filename + ".gz")
    if download:
        with urllib.request.urlopen(record["url"], timeout=90) as response:
            data = response.read()
        if hashlib.sha256(data).hexdigest() != record["sha256"]:
            raise ValueError(f"Upstream checksum mismatch: {filename}")
        path.write_bytes(gzip.compress(data, mtime=0))
    data = gzip.decompress(path.read_bytes())
    if hashlib.sha256(data).hexdigest() != record["sha256"]:
        raise ValueError(f"Source checksum mismatch: {filename}")
    return data


def collect_entries(manifest: dict, download: bool = False) -> tuple[list[dict], dict]:
    grouped: dict[tuple[str, str], dict] = {}
    stats = Counter()
    for filename, pos in TABLES.items():
        data = source_bytes(filename, manifest, download)
        reader = csv.DictReader(io.StringIO(data.decode("utf-8")), delimiter="\t")
        required = {"bare", "accented", "translations_en"}
        if not required.issubset(reader.fieldnames or []):
            raise ValueError(f"Unexpected source columns: {filename}")
        for row in reader:
            stats["source_rows"] += 1
            if None in row or any(row.get(key) is None for key in required):
                stats["unparseable_rows"] += 1
                continue
            russian = unicodedata.normalize("NFC", row["bare"].strip())
            english = row["translations_en"].strip()
            if not russian or not re.search("[а-яёА-ЯЁ]", russian):
                stats["invalid_headword_rows"] += 1
                continue
            if not english:
                stats["missing_english_rows_excluded"] += 1
                continue
            # Homographs of the same source POS are combined with their senses;
            # different POS remain independent lexical entries. ё is preserved.
            identity = (russian.casefold(), pos)
            forms = {k: unicode_stress(v.strip()) for k, v in row.items() if k not in NON_FORMS and v and v.strip()}
            stressed = unicode_stress(row["accented"].strip() or russian)
            if identity in grouped:
                stats["duplicate_source_rows_merged"] += 1
                entry = grouped[identity]
                if english not in entry["meanings"]:
                    entry["meanings"].append(english)
                if stressed not in entry["stress_variants"]:
                    entry["stress_variants"].append(stressed)
                for key, value in forms.items():
                    if key not in entry["forms"]:
                        entry["forms"][key] = value
                    elif value != entry["forms"][key]:
                        entry["forms"][key] += " / " + value
                continue
            identifier = "openrussian:" + pos + ":" + hashlib.sha256(identity[0].encode()).hexdigest()[:24]
            grouped[identity] = {
                "id": identifier, "russian": russian, "stressed": stressed,
                "stress_variants": [stressed], "chinese": "", "meanings": [english],
                "part_of_speech": pos, "gender": row.get("gender", ""), "aspect": row.get("aspect", ""),
                "frequency_rank": None, "level": "", "category": "", "source": manifest["repository"] + "/tree/" + manifest["commit"],
                "license": manifest["license"], "review_status": "pending", "forms": forms,
                "examples": [], "search_key": search_key(russian), "tier": 3,
                "entry_kind": "phrase" if re.search(r"\s", russian) else "word",
            }
    return sorted(grouped.values(), key=lambda entry: entry["id"]), dict(stats)


def apply_teaching_pack(entries: list[dict], path: Path | None) -> tuple[list[dict], list[tuple]]:
    """Validate an editorial pack before touching the existing database."""
    if path is None:
        return entries, []
    package = json.loads(path.read_text())
    if not isinstance(package, dict) or package.get("schema_version") != 1 or not isinstance(package.get("entries"), list):
        raise ValueError("Teaching pack requires schema_version=1 and an entries array")
    index = {item["id"]: item for item in entries}
    identities = {(item["russian"].casefold(), item["part_of_speech"]): item["id"] for item in entries}
    seen = set()
    reviews = []
    required = ["id", "russian", "chinese", "part_of_speech", "source", "license", "reviewed_by", "reviewed_at", "review_reference"]
    for record in package["entries"]:
        if not isinstance(record, dict) or any(not isinstance(record.get(k), str) or not record[k].strip() for k in required):
            raise ValueError("Teaching entry is missing required text, source, license or review metadata")
        identifier = record["id"]
        if identifier in seen:
            raise ValueError(f"Duplicate teaching ID: {identifier}")
        seen.add(identifier)
        if record.get("tier") not in (1, 2) or isinstance(record.get("tier"), bool):
            raise ValueError("Teaching tier must be 1 or 2; tier 2 expands the cumulative 3,000-word foundation")
        if record.get("review_status") != "verified":
            raise ValueError("Teaching pack must declare reviewed content; pending data stays lookup-only")
        if not re.search("[\u3400-\u9fff]", record["chinese"]):
            raise ValueError("Teaching entries require an actual Chinese definition")
        if record["license"] not in ("CC-BY-SA-4.0", "CC-BY-4.0", "CC0-1.0"):
            raise ValueError("Teaching pack requires an explicit compatible supported license")
        russian = unicodedata.normalize("NFC", record["russian"].strip())
        identity = (russian.casefold(), record["part_of_speech"])
        if identity in identities and identities[identity] != identifier:
            raise ValueError("Duplicate lemma/POS under a different ID; enrich the existing ID instead")
        if identifier in index and (index[identifier]["russian"].casefold(), index[identifier]["part_of_speech"]) != identity:
            raise ValueError("An existing ID cannot be reassigned to a different lexical entry")
        old = index.get(identifier)
        stressed = record.get("stressed", "").strip()
        if not stressed or search_key(stressed) != search_key(russian):
            raise ValueError("Reviewed stressed headword must match the Russian lemma")
        if len(re.findall("[" + VOWELS + "]", russian)) > 1 and ACCENT not in unicodedata.normalize("NFD", stressed) and "ё" not in stressed.casefold():
            raise ValueError("Multisyllabic teaching entries require sourced stress or ё")
        rank = record.get("frequency_rank")
        if rank is not None and (not isinstance(rank, int) or isinstance(rank, bool) or rank <= 0):
            raise ValueError("frequency_rank must be a documented positive integer or null")
        updated = dict(old) if old else {
            "id": identifier, "russian": russian, "meanings": [], "part_of_speech": record["part_of_speech"],
            "gender": "", "aspect": "", "forms": {}, "examples": [], "entry_kind": "phrase" if re.search(r"\s", russian) else "word",
        }
        updated.update({"stressed": stressed, "stress_variants": record.get("stress_variants", [stressed]), "chinese": record["chinese"].strip(),
                        "frequency_rank": rank, "level": record.get("level", ""), "category": record.get("category", ""),
                        "source": (old["source"] + " ; " if old else "") + record["source"], "license": "CC-BY-SA-4.0",
                        "review_status": "verified", "search_key": search_key(russian), "tier": record["tier"]})
        index[identifier] = updated
        identities[identity] = identifier
        reviews.append((identifier, record["reviewed_by"], record["reviewed_at"], record["review_reference"], record["license"]))
    core = sum(item["tier"] == 1 for item in index.values())
    foundation = sum(item["tier"] in (1, 2) for item in index.values())
    if core > 1000 or foundation > 3000:
        raise ValueError("Teaching packs exceed the 1,000 core / cumulative 3,000 foundation plan")
    return sorted(index.values(), key=lambda item: item["id"]), reviews


SCHEMA = """
PRAGMA user_version=1;
CREATE TABLE metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL) WITHOUT ROWID;
CREATE TABLE entries (
 id TEXT PRIMARY KEY, russian TEXT NOT NULL, stressed TEXT NOT NULL,
 chinese TEXT NOT NULL, english TEXT NOT NULL, part_of_speech TEXT NOT NULL,
 gender TEXT NOT NULL, aspect TEXT NOT NULL, frequency_rank INTEGER,
 level TEXT NOT NULL, category TEXT NOT NULL, source TEXT NOT NULL,
 license TEXT NOT NULL, review_status TEXT NOT NULL, forms TEXT NOT NULL,
 examples TEXT NOT NULL, search_key TEXT NOT NULL, tier INTEGER NOT NULL CHECK(tier IN (1,2,3)),
 entry_kind TEXT NOT NULL, stress_variants TEXT NOT NULL,
 search_text TEXT NOT NULL
);
CREATE TABLE forms (
 form_key TEXT NOT NULL, entry_id TEXT NOT NULL REFERENCES entries(id),
 PRIMARY KEY(form_key,entry_id)
) WITHOUT ROWID;
CREATE TABLE reviews (
 entry_id TEXT PRIMARY KEY REFERENCES entries(id), reviewed_by TEXT NOT NULL,
 reviewed_at TEXT NOT NULL, review_reference TEXT NOT NULL, original_license TEXT NOT NULL
) WITHOUT ROWID;
CREATE INDEX entries_search_key ON entries(search_key);
CREATE INDEX entries_tier ON entries(tier,frequency_rank);
CREATE INDEX entries_part_of_speech ON entries(part_of_speech);
"""


def build(database: Path = DATABASE, download: bool = False, teaching_pack: Path | None = None) -> dict:
    manifest = json.loads((SOURCE / "manifest.json").read_text())
    entries, stats = collect_entries(manifest, download)
    entries, reviews = apply_teaching_pack(entries, teaching_pack)
    database.parent.mkdir(parents=True, exist_ok=True)
    # Rebuilding content must never operate on the separate user progress store.
    with tempfile.NamedTemporaryFile(dir=database.parent, suffix=".sqlite", delete=False) as tmp:
        temporary = Path(tmp.name)
    try:
        connection = sqlite3.connect(temporary)
        connection.executescript(SCHEMA)
        for entry in entries:
            english = " | ".join(entry["meanings"])
            values = [entry[k] for k in ["id", "russian", "stressed", "chinese"]]
            values += [english] + [entry[k] for k in ["part_of_speech", "gender", "aspect", "frequency_rank", "level", "category", "source", "license", "review_status"]]
            values += [json.dumps(entry["forms"], ensure_ascii=False), json.dumps(entry["examples"], ensure_ascii=False), entry["search_key"], entry["tier"], entry["entry_kind"], json.dumps(entry["stress_variants"], ensure_ascii=False), search_key(entry["russian"] + " " + entry["chinese"] + " " + english)]
            connection.execute("INSERT INTO entries VALUES (" + ",".join("?" for _ in values) + ")", values)
            forms = {entry["search_key"]}
            for source_form in entry["forms"].values():
                for variant in re.split(r"[,;/]", source_form):
                    key = search_key(variant)
                    if key and re.search("[а-яё]", key):
                        forms.add(key)
            connection.executemany("INSERT OR IGNORE INTO forms VALUES (?,?)", ((key, entry["id"]) for key in sorted(forms)))
        connection.executemany("INSERT INTO reviews VALUES (?,?,?,?,?)", reviews)
        metadata = {"source": manifest["repository"], "source_commit": manifest["commit"], "license": manifest["license"], "schema_version": "1", "source_statistics": json.dumps(stats, sort_keys=True), "chinese_review_status": "No Chinese translations supplied by this source; all imported entries are lookup-only."}
        connection.executemany("INSERT INTO metadata VALUES (?,?)", sorted(metadata.items()))
        connection.commit()
        assert connection.execute("PRAGMA integrity_check").fetchone()[0] == "ok"
        assert not connection.execute("PRAGMA foreign_key_check").fetchall()
        connection.execute("VACUUM")
        connection.close()
        temporary.replace(database)
    except BaseException:
        temporary.unlink(missing_ok=True)
        raise
    return {**stats, "entries": len(entries), "database": str(database), "database_bytes": database.stat().st_size}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--download", action="store_true", help="Refresh pinned TSV snapshots via HTTPS; expected SHA-256 must match.")
    parser.add_argument("--output", type=Path, default=DATABASE)
    parser.add_argument("--teaching-pack", type=Path, help="Optional independently reviewed, licensed Chinese teaching JSON pack")
    arguments = parser.parse_args()
    print(json.dumps(build(arguments.output, arguments.download, arguments.teaching_pack), ensure_ascii=False, indent=2))
