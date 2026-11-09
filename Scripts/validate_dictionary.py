#!/usr/bin/env python3
"""Measure the shipped dictionary; targets and missing content are never counted as data."""
from __future__ import annotations

import argparse
import gzip
import hashlib
import json
import platform
import sqlite3
import statistics
import time
import unicodedata
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_DATABASE = ROOT / "Resources/dictionary.sqlite"


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def inspect_sources(source: Path) -> list[dict]:
    manifest = json.loads((source / "manifest.json").read_text())
    records = []
    for name, expected in manifest["files"].items():
        compressed = (source / (name + ".gz")).read_bytes()
        raw = gzip.decompress(compressed)
        records.append({"name": name, "raw_bytes": len(raw),
                        "raw_sha256_matches": sha256(raw) == expected["sha256"],
                        "gzip_sha256_matches": sha256(compressed) == expected["gzip_sha256"],
                        "raw_size_matches": len(raw) == expected["raw_bytes"]})
    return records


def benchmark(connection: sqlite3.Connection, repeats: int) -> list[dict]:
    queries = [
        ("俄语前缀 мам", "SELECT id FROM entries WHERE search_key>=? AND search_key<? ORDER BY search_key LIMIT 100", ("мам", "мам\U0010ffff")),
        ("词形 мамы → 原形", "SELECT id FROM entries WHERE id IN (SELECT entry_id FROM forms WHERE form_key=?) LIMIT 100", ("мамы",)),
        ("英文释义 hospital", "SELECT id FROM entries WHERE lower(english) LIKE ? OR chinese LIKE ? ORDER BY search_key LIMIT 100", ("%hospital%", "%hospital%")),
        ("中文 医院（当前预期无结果）", "SELECT id FROM entries WHERE chinese LIKE ? ORDER BY search_key LIMIT 100", ("%医院%",)),
    ]
    results = []
    for name, sql, params in queries:
        samples = []
        count = 0
        for _ in range(max(1, repeats)):
            started = time.perf_counter()
            count = len(connection.execute(sql, params).fetchall())
            samples.append((time.perf_counter() - started) * 1000)
        ordered = sorted(samples)
        results.append({"query": name, "result_count": count, "runs": len(samples),
                        "median_ms": round(statistics.median(samples), 3),
                        "p95_ms": round(ordered[min(len(ordered)-1, int(len(ordered)*0.95))], 3),
                        "first_run_ms": round(samples[0], 3)})
    return results


def validate(database: Path = DEFAULT_DATABASE, source: Path = ROOT / "Data/openrussian", repeats: int = 10) -> dict:
    manifest = json.loads((source / "manifest.json").read_text())
    with sqlite3.connect(database.resolve().as_uri() + "?mode=ro", uri=True) as connection:
        connection.row_factory = sqlite3.Row
        integrity = connection.execute("PRAGMA integrity_check").fetchone()[0]
        foreign_key_errors = len(connection.execute("PRAGMA foreign_key_check").fetchall())
        rows = connection.execute("SELECT * FROM entries").fetchall()
        metadata = dict(connection.execute("SELECT key,value FROM metadata"))
        tiers = Counter(str(row["tier"]) for row in rows)
        parts = Counter(row["part_of_speech"] for row in rows)
        kinds = Counter(row["entry_kind"] for row in rows)
        reviews = Counter(row["review_status"] for row in rows)
        lemma_keys = Counter((unicodedata.normalize("NFC", row["russian"]).casefold(), row["part_of_speech"]) for row in rows)
        meaning_keys = Counter((unicodedata.normalize("NFC", row["russian"]).casefold(), row["part_of_speech"], " ".join(row["english"].casefold().split()), " ".join(row["chinese"].split())) for row in rows)
        missing = {field: sum(not row[field] for row in rows) for field in [
            "russian", "stressed", "chinese", "english", "part_of_speech", "gender", "aspect",
            "frequency_rank", "level", "category", "source", "license"]}
        acute = sum("\u0301" in unicodedata.normalize("NFD", row["stressed"]) for row in rows)
        yo = sum("ё" in row["stressed"].casefold() for row in rows)
        stress = sum("\u0301" in unicodedata.normalize("NFD", row["stressed"]) or "ё" in row["stressed"].casefold() for row in rows)
        with_forms = with_examples = malformed_json = 0
        for row in rows:
            for field, expected_type in [("forms", dict), ("examples", list), ("stress_variants", list)]:
                try:
                    decoded = json.loads(row[field])
                    if not isinstance(decoded, expected_type):
                        malformed_json += 1
                    elif field == "forms":
                        with_forms += bool(decoded)
                    elif field == "examples":
                        with_examples += bool(decoded)
                except (ValueError, TypeError):
                    malformed_json += 1
        bad_teaching = sum(row["tier"] in (1, 2) and (row["review_status"] != "verified" or not row["chinese"].strip()) for row in rows)
        source_checks = inspect_sources(source)
        report = {
            "database": str(database.relative_to(ROOT)) if database.is_relative_to(ROOT) else str(database),
            "database_bytes": database.stat().st_size, "database_sha256": sha256(database.read_bytes()),
            "source_repository": manifest["repository"], "source_commit": manifest["commit"],
            "source_license": manifest["license"], "source_checks": source_checks,
            "schema_version": connection.execute("PRAGMA user_version").fetchone()[0],
            "sqlite_integrity": integrity, "foreign_key_errors": foreign_key_errors,
            "total_entries": len(rows), "unique_ids": len({row["id"] for row in rows}),
            "unique_lemma_pos": len(lemma_keys), "unique_russian_lemmas": len({row["russian"].casefold() for row in rows}),
            "duplicate_lemma_pos_rows": sum(count-1 for count in lemma_keys.values()),
            "duplicate_lemma_pos_meaning_rows": sum(count-1 for count in meaning_keys.values()),
            "entry_kinds": dict(kinds), "tiers": dict(tiers), "parts_of_speech": dict(parts),
            "review_status": dict(reviews), "missing_fields": missing,
            "chinese_entries": len(rows)-missing["chinese"], "acute_stress_entries": acute,
            "yo_entries": yo, "explicit_stress_or_yo_entries": stress,
            "entries_with_forms": with_forms, "entries_with_examples": with_examples,
            "form_index_rows": connection.execute("SELECT count(*) FROM forms").fetchone()[0],
            "unique_search_forms": connection.execute("SELECT count(DISTINCT form_key) FROM forms").fetchone()[0],
            "malformed_json_fields": malformed_json, "invalid_teaching_entries": bad_teaching,
            "core_teaching_entries": sum(row["tier"] == 1 and row["review_status"] == "verified" and bool(row["chinese"]) for row in rows),
            "foundation_teaching_entries": sum(row["tier"] in (1, 2) and row["review_status"] == "verified" and bool(row["chinese"]) for row in rows),
            "source_import_statistics": json.loads(metadata["source_statistics"]),
            "benchmark": benchmark(connection, repeats), "benchmark_platform": platform.system(),
        }
        report["valid"] = all([
            integrity == "ok", not foreign_key_errors, report["schema_version"] == 1,
            len(rows) == report["unique_ids"], not report["duplicate_lemma_pos_rows"],
            not malformed_json, not bad_teaching, not missing["russian"], not missing["source"], not missing["license"],
            all(row["tier"] in (1, 2, 3) for row in rows),
            all(all(item[key] for key in ("raw_sha256_matches", "gzip_sha256_matches", "raw_size_matches")) for item in source_checks),
            metadata["source_commit"] == manifest["commit"],
        ])
        return report


def markdown(report: dict) -> str:
    total = report["total_entries"]
    def percentage(count: int) -> str:
        return f"{count / total * 100:.2f}%" if total else "0.00%"
    lines = ["# 词库质量报告", "", "由 `python3 Scripts/validate_dictionary.py` 对实际数据库和固定来源快照生成。", "",
             f"- 实际词条：**{total:,}**；唯一 ID：{report['unique_ids']:,}；去重后的原形＋词性：{report['unique_lemma_pos']:,}。",
             f"- 单词词条：{report['entry_kinds'].get('word', 0):,}；短语词条：{report['entry_kinds'].get('phrase', 0):,}。短语以原形含空白字符识别。",
             f"- 不区分词性的原形数量：{report['unique_russian_lemmas']:,}；不同词性条目单独计数，同一条目的词义与词形不增加词条数。",
             f"- 核心目标 1,000：实际已审校中文学习词 **{report['core_teaching_entries']}**。",
             f"- 基础目标 3,000（包含核心 1,000）：实际已审校中文学习词 **{report['foundation_teaching_entries']}**。",
             "- 扩展查询条目不等于中文教学词库；当前不能宣称已完成 1,000/3,000 中文学习内容。", "",
             "## 内容覆盖", "", "| 指标 | 实际数量 | 占全部词条 |", "| --- | ---: | ---: |"]
    coverage = [("中文释义", report["chinese_entries"]), ("英文释义", total-report["missing_fields"]["english"]),
                ("重音符 U+0301", report["acute_stress_entries"]), ("包含 ё", report["yo_entries"]),
                ("明确重音符或 ё（去重后）", report["explicit_stress_or_yo_entries"]),
                ("有变化词形", report["entries_with_forms"]), ("例句", report["entries_with_examples"]),
                ("来源", total-report["missing_fields"]["source"]), ("许可证", total-report["missing_fields"]["license"])]
    lines += [f"| {label} | {count:,} | {percentage(count)} |" for label, count in coverage]
    lines += ["", "重音统计只表示来源带有标记，不代表本项目已人工审校；单音节词无显式重音也可能有效。ё 原文保留，仅搜索键折叠为 е。", "",
              "## 等级和字段缺失", "", f"tier 分布：`{json.dumps(report['tiers'], ensure_ascii=False, sort_keys=True)}`。",
              f"审校状态：`{json.dumps(report['review_status'], ensure_ascii=False, sort_keys=True)}`。",
              f"词性分布：`{json.dumps(report['parts_of_speech'], ensure_ascii=False, sort_keys=True)}`。", "",
              "| 字段 | 缺失数量 | 缺失比例 |", "| --- | ---: | ---: |"]
    lines += [f"| {field} | {count:,} | {percentage(count)} |" for field, count in report["missing_fields"].items()]
    lines += ["", "性别仅适用于部分词性，动词体仅适用于动词；上述全库缺失率不等同于数据错误。词频、CEFR/内部等级和生活分类没有可靠来源时保持为空，不以文件顺序代替频率。", "",
              "## 去重、词形与解析", "", f"- 同原形＋词性重复行：{report['duplicate_lemma_pos_rows']}。",
              f"- 同原形＋词性＋相同释义重复行：{report['duplicate_lemma_pos_meaning_rows']}。",
              f"- 词形索引记录：{report['form_index_rows']:,}；唯一查询形式：{report['unique_search_forms']:,}。词形不作为新词条计数。",
              f"- 无法解析的数据库 JSON 字段：{report['malformed_json_fields']}；非法教学条目：{report['invalid_teaching_entries']}。",
              f"- 上游导入统计：`{json.dumps(report['source_import_statistics'], ensure_ascii=False, sort_keys=True)}`。",
              "- 同一原形＋词性的多行合并释义与重音变体；不同原形或词性保留独立 ID。语义重复统计不能代替语言专家判定近义词。", "",
              "## 完整性和来源", "", f"- SQLite 完整性：`{report['sqlite_integrity']}`；外键错误：{report['foreign_key_errors']}；结构版本：{report['schema_version']}。",
              f"- 自动结构验收：**{'通过' if report['valid'] else '失败'}**。这不代表教学内容审校通过。",
              f"- 数据库：`{report['database']}`，{report['database_bytes']:,} 字节。",
              f"- SHA-256：`{report['database_sha256']}`。",
              f"- 来源：{report['source_repository']}，固定提交 `{report['source_commit']}`。",
              f"- 数据许可：`{report['source_license']}`，署名与转换说明见 [DATA_LICENSES.md](DATA_LICENSES.md)。",
              "- 4 份压缩源文件均核对原始字节 SHA-256、压缩文件 SHA-256 及原始大小。", "",
              "## 查询计时", "", f"以下为当前 {report['benchmark_platform']} 执行环境的 SQLite 本地查询实测，缓存可能已预热；不能作为 iPhone 真机性能验收。每次最多返回 100 条。",
              "", "| 查询 | 返回数 | 次数 | 中位数 ms | P95 ms | 首次 ms |", "| --- | ---: | ---: | ---: | ---: | ---: |"]
    lines += [f"| {item['query']} | {item['result_count']} | {item['runs']} | {item['median_ms']} | {item['p95_ms']} | {item['first_run_ms']} |" for item in report["benchmark"]]
    lines += ["", "中文查询返回 0 是当前中文数据缺失的真实结果。前缀与词形查询使用索引；英文/中文子串匹配会扫描词条，应继续在目标 iPhone 上验证。", "",
              "## 未完成内容", "", "已审校中文核心 1,000 词、累计基础 3,000 词、可靠词频等级、教学例句、完整生活分类与医学/牙科专业审校均未完成。词典规模已支持 30,000+ 查询条目，但不能据此宣称上述教学模块完成。", ""]
    return "\n".join(lines)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--database", type=Path, default=DEFAULT_DATABASE)
    parser.add_argument("--report", type=Path, default=ROOT / "docs/DICTIONARY_REPORT.md")
    parser.add_argument("--json", type=Path)
    parser.add_argument("--repeats", type=int, default=10)
    args = parser.parse_args()
    result = validate(args.database, repeats=args.repeats)
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(markdown(result), encoding="utf-8")
    if args.json:
        args.json.write_text(json.dumps(result, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
    print(json.dumps({key: result[key] for key in ["valid", "total_entries", "chinese_entries", "core_teaching_entries", "foundation_teaching_entries", "form_index_rows", "benchmark"]}, ensure_ascii=False, indent=2))
    raise SystemExit(0 if result["valid"] else 1)
