"""Inventory the user-provided task pack; never import its DATA or run programs."""

from __future__ import annotations

import collections
import hashlib
import json
import re
import sys
import zipfile
from datetime import datetime, timezone
from pathlib import Path

import audit_content as core


ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "docs" / "cg71_content_audit" / "sources"
SOURCE = Path(r"D:\BaiduNetdiskDownload\全部任务共享\全部任务共享")
sys.path.insert(0, str(Path(__file__).resolve().parent / ".deps"))


def text(data: bytes) -> str:
    if data.startswith((b"\xff\xfe", b"\xfe\xff")):
        return data.decode("utf-16", errors="replace")
    return core.label(data)


def main() -> None:
    import rarfile

    source = SOURCE.resolve(strict=True)
    current_maps = json.loads((OUT.parent / "maps.json").read_text(encoding="utf-8"))
    current_floors = {m["floor"]: m for m in current_maps}
    current_tasks = json.loads((OUT.parent / "tasks.json").read_text(encoding="utf-8"))
    missing_scripts = {task["script"].casefold(): task["script"] for task in current_tasks if not task["present"]}
    comparison = json.loads((OUT.parent / "target_comparison.json").read_text(encoding="utf-8"))
    skill_groups = [{"name": check["name"], "aliases": check["aliases"]} for check in comparison["advanced_skill_checks"]]
    features = json.loads((OUT.parent / "version_gaps.json").read_text(encoding="utf-8"))["features"]
    warp_candidate = json.loads((OUT / "angel_warp_candidate.json").read_text(encoding="utf-8"))
    angel_floors = sorted({row[1] for row in warp_candidate["rows"]} | {row[4] for row in warp_candidate["rows"]})
    keywords = {
        "angel_mainline": ["天使大陆", "天使大陸", "军团的逆袭", "軍團的逆襲", "曙光骑士团", "曙光騎士團"],
        "time_gate": ["时空之门", "時空之門"],
        "new_regions": ["露毕恩", "露畢恩", "卢比恩", "盧比恩", "孤峰城"],
        "craft_professions": ["宠物服装制造", "寵物服裝製造", "宠物装甲制造", "寵物裝甲製造",
                              "宠物项圈制造", "寵物項圈製造", "宠物晶石制造", "寵物晶石製造"],
    }
    maps, invalid_maps, recoverable, archive_indices = [], [], [], []
    matches = collections.defaultdict(list)
    tables = collections.defaultdict(list)
    files = sorted(p for p in source.rglob("*") if p.is_file())
    for index, path in enumerate(files):
        relative = path.relative_to(source).as_posix()
        with path.open("rb") as stream:
            header = stream.read(20)
        if header.startswith(b"LS2MAP"):
            data = path.read_bytes()
            try:
                record = core.native_map(data)
                record.update(path=relative, sha256=hashlib.sha256(data).hexdigest())
                existing = current_floors.get(record["floor"])
                record["current_server_floor_present"] = existing is not None
                record["matches_current_server_sha256"] = existing is not None and existing["sha256"] == record["sha256"]
                maps.append(record)
            except ValueError as exc:
                invalid_maps.append({"path": relative, "error": str(exc)})
        if path.name.casefold() in missing_scripts:
            recoverable.append({"script": missing_scripts[path.name.casefold()], "path": relative,
                                "sha256": core.sha256(path.read_bytes())})
        if path.suffix.lower() in {".txt", ".ini"}:
            content = text(path.read_bytes())
            for group, words in keywords.items():
                hits = [word for word in words if word in content or word in relative]
                if hits:
                    matches[group].append({"path": relative, "keywords": hits})
            if path.name.lower() in {"skill.txt", "tech.txt", "jobs.txt", "itemrecipe.txt"}:
                data = path.read_bytes()
                named = []
                id_column = {"skill.txt": 1, "tech.txt": 3, "jobs.txt": 2, "itemrecipe.txt": 1}[path.name.lower()]
                for line, columns in core.records(data):
                    if columns:
                        named.append({"line": line, "name": core.label(columns[0]),
                                      "id": core.number(columns[id_column]) if len(columns) > id_column else None})
                tables[path.name.lower()].append({"path": relative, "sha256": core.sha256(data), "records": named})
        if path.suffix.lower() in {".rar", ".zip"}:
            archive_record = {"path": relative, "bytes": path.stat().st_size, "members": []}
            try:
                if path.suffix.lower() == ".rar":
                    with rarfile.RarFile(path, charset="gbk") as package:
                        archive_record["members"] = [{"name": i.filename, "bytes": i.file_size,
                                                      "directory": i.isdir()} for i in package.infolist()]
                        archive_record["password_needed"] = package.needs_password()
                else:
                    with zipfile.ZipFile(path, metadata_encoding="gbk") as package:
                        archive_record["members"] = [{"name": i.filename, "bytes": i.file_size,
                                                      "directory": i.is_dir()} for i in package.infolist()]
                        archive_record["password_needed"] = any(i.flag_bits & 1 for i in package.infolist())
                for member in archive_record["members"]:
                    basename = Path(member["name"].replace("\\", "/")).name.casefold()
                    if basename in missing_scripts:
                        recoverable.append({"script": missing_scripts[basename], "archive": relative,
                                            "member": member["name"], "content_verified": False})
            except Exception as exc:
                archive_record["error"] = f"{type(exc).__name__}: {exc}"
            archive_indices.append(archive_record)
        if index and index % 4000 == 0:
            print(f"Inspected {index}/{len(files)} source files.", flush=True)

    grouped = collections.defaultdict(list)
    for record in maps:
        grouped[record["floor"]].append(record)
    absent = sorted(floor for floor in grouped if floor not in current_floors)
    conflicting = [{"floor": floor, "variants": len({m["sha256"] for m in candidates}),
                    "paths": [m["path"] for m in candidates]}
                   for floor, candidates in grouped.items() if len({m["sha256"] for m in candidates}) > 1]
    advanced = []
    for group in skill_groups:
        found = []
        for table_name in ["skill.txt", "tech.txt"]:
            for table in tables[table_name]:
                for row in table["records"]:
                    if any(row["name"] == alias or row["name"].startswith(alias + "LV")
                           for alias in group["aliases"]):
                        found.append({"table": table_name, "path": table["path"], **row})
        advanced.append({**group, "name_matches_only": found})
    report = {
        "checked_utc": datetime.now(timezone.utc).isoformat(), "source": str(source),
        "scope": "Read-only source inventory and selected Taiwan 7.1 candidate checks; not a complete quest audit.",
        "stats": {"files": len(files), "directories": sum(p.is_dir() for p in source.rglob("*")),
                  "native_map_files": len(maps), "native_map_unique_floors": len(grouped),
                  "invalid_native_maps": len(invalid_maps), "floors_absent_from_current_server": len(absent),
                  "same_floor_different_payload_groups": len(conflicting), "nested_archives": len(archive_indices),
                  "nested_archive_index_errors": sum("error" in a for a in archive_indices),
                  "table_files": {name: len(entries) for name, entries in tables.items()}},
        "top_level_directories": sorted(p.name for p in source.iterdir() if p.is_dir()),
        "missing_script_candidates": recoverable,
        "angel_required_floors": [{"floor": floor, "source_candidates": grouped.get(floor, [])} for floor in angel_floors],
        "selected_target_keyword_matches": dict(matches), "advanced_skill_table_name_matches": advanced,
        "new_floor_ids": absent, "different_source_payloads_same_floor": conflicting,
        "maps": maps, "invalid_maps": invalid_maps, "table_inventory": dict(tables),
        "nested_archive_indices": archive_indices,
        "game_data_imported": False, "archive_programs_executed": False,
        "limitations": ["A new floor ID is not proof of new official-version content.",
                        "Chinese task names and matching skill names do not establish complete dependencies or correct parameters.",
                        "RAR entries were only indexed; compressed member payloads were not extracted or scanned."],
    }
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "shared_task_pack_inventory.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"stats": report["stats"], "angel_maps_found": [floor for floor in angel_floors if floor in grouped],
                      "recoverable_missing_scripts": recoverable,
                      "target_keywords": {k: len(v) for k, v in matches.items()},
                      "advanced_skill_groups_with_name_candidates": [a["name"] for a in advanced if a["name_matches_only"]]},
                     ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
