"""Read-only CGMSV content inventory. Writes reports, never game DATA.

Python 3.10+, standard library only. Text labels are decoded for reporting;
source bytes are neither converted nor rewritten. This is a local dependency
audit, not an assertion that every official 7.1 feature is represented.
"""
from __future__ import annotations

import argparse
import collections
import csv
import hashlib
import json
import re
import struct
from datetime import datetime, timezone
from pathlib import Path


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def label(data):
    try:
        return data.decode("utf-8")
    except UnicodeDecodeError:
        return data.decode("gbk", errors="replace")


def number(value):
    try:
        return int(value)
    except (ValueError, TypeError):
        return None


def records(data):
    for line, raw in enumerate(data.splitlines(), 1):
        if raw.strip() and not raw.lstrip().startswith((b"#", b"//")):
            yield line, raw.split(b"\t")


def native_map(data):
    """Observed LS2MAP variants, cross-checked against local mapid.log.

    0xffff is an extension marker, NOT floor 65535. Its floor is a BE
    uint32 at +48. Keep the remainder of the extension opaque. Payload
    sizes are checked; this does not prove walkability or graphics loading.
    """
    if not data.startswith(b"LS2MAP"):
        return None
    if len(data) < 44:
        raise ValueError("truncated LS2MAP header")
    marker = struct.unpack_from(">H", data, 6)[0]
    width, height = struct.unpack_from(">HH", data, 40)
    header = 44
    cell_bytes = 4
    floor = marker
    variant = "LS2MAP"
    if marker == 65535:
        if len(data) < 60 or struct.unpack_from(">I", data, 44)[0] != 16:
            raise ValueError("unsupported LS2MAP extension")
        floor = struct.unpack_from(">I", data, 48)[0]
        header, cell_bytes, variant = 60, 6, "LS2MAP extended"
    expected = header + width * height * cell_bytes
    if not width or not height or len(data) != expected:
        raise ValueError(f"invalid dimensions/payload: {width}x{height}, {len(data)} != {expected}")
    raw_name = data[8:40].split(b"\0", 1)[0]
    return {"floor": floor, "name": label(raw_name), "name_hex": raw_name.hex(),
            "width": width, "height": height, "variant": variant,
            "header_bytes": header, "cell_bytes": cell_bytes, "bytes": len(data)}


def client_map(data):
    if not data.startswith(b"MAP") or len(data) < 20:
        raise ValueError("unsupported client map header")
    width, height = struct.unpack_from("<II", data, 12)
    if not width or not height or len(data) != 20 + width * height * 6:
        raise ValueError("invalid client cache dimensions/payload")
    return {"width": width, "height": height, "bytes": len(data)}


def dump_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def dump_csv(path, rows, columns):
    with path.open("w", encoding="utf-8-sig", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=columns, extrasaction="ignore")
        writer.writeheader()
        for row in rows:
            writer.writerow({k: json.dumps(v, ensure_ascii=False) if isinstance(v, (list, dict)) else v
                             for k, v in row.items() if k in columns})


def audit(root, out):
    root = root.resolve()
    out.mkdir(parents=True, exist_ok=True)
    server = root / "gmsv"
    inputs = {}
    findings = []

    def read(path):
        data = path.read_bytes()
        inputs[path.relative_to(root).as_posix()] = {"bytes": len(data), "sha256": sha256(data)}
        return data

    def issue(area, kind, **details):
        findings.append({**details, "category": area, "kind": kind})

    setup = {}
    for raw in read(server / "setup.cf").splitlines():
        if raw.strip() and not raw.lstrip().startswith(b"#") and b"=" in raw:
            key, value = raw.split(b"=", 1)
            setup[key.decode("ascii", errors="ignore").strip()] = value.strip().decode("ascii", errors="ignore")

    def configured(key, default):
        path = Path(setup.get(key, default))
        return path if path.is_absolute() else server / path

    paths = {key: configured(key, default) for key, default in {
        "mapdir": "data/map", "npcfile": "data/npc.txt", "warpfile": "data/warp.txt",
        "dungeonconffile": "data/dungeonconf.txt", "skillfile": "data/skill.txt",
        "skilllvfile": "data/skilllv.txt", "techfile": "data/tech.txt", "jobsfile": "data/jobs.txt",
        "itemfile": "data/itemset.txt", "techareafile": "data/techarea.txt",
        "maptilefile": "data/map/mapset.txt"}.items()}

    maps = []
    for path in sorted(paths["mapdir"].iterdir()):
        if not path.is_file():
            continue
        # Do not hash non-map files twice; map tile definitions are handled below.
        with path.open("rb") as stream:
            magic = stream.read(6)
        if magic != b"LS2MAP":
            continue
        data = read(path)
        try:
            entry = native_map(data)
            entry.update(path=path.relative_to(root).as_posix(), sha256=sha256(data))
            maps.append(entry)
        except ValueError as error:
            issue("maps", "invalid_native_map", path=path.relative_to(root).as_posix(), error=str(error))
    by_floor = collections.defaultdict(list)
    for entry in maps:
        by_floor[entry["floor"]].append(entry)
    for floor, entries in by_floor.items():
        if len(entries) > 1:
            issue("maps", "duplicate_floor", floor=floor, paths=[e["path"] for e in entries])

    map_log = server / "log/mapid.log"
    logged = {}
    if map_log.exists():
        for raw in read(map_log).splitlines():
            match = re.match(rb"(\d+)\s+(.+)", raw)
            if match:
                logged[int(match[1])] = label(match[2])
    for entry in maps:
        entry["listed_in_startup_map_log"] = entry["floor"] in logged

    caches = []
    for path in sorted((root / "map").glob("*/*.dat")):
        try:
            data = read(path)
            entry = client_map(data)
            entry.update(floor=number(path.stem), map_type=number(path.parent.name),
                         path=path.relative_to(root).as_posix())
            entry["server_map_present"] = entry["floor"] in by_floor if entry["map_type"] == 0 else None
            caches.append(entry)
        except ValueError as error:
            issue("maps", "invalid_client_cache", path=path.relative_to(root).as_posix(), error=str(error))

    dungeon_rows = list(records(read(paths["dungeonconffile"])))
    # c[49] is the observed generation floor, not a fixed LS2MAP requirement.
    dynamic_floors = {number(c[49]) for _, c in dungeon_rows if len(c) > 49}
    references = []

    def map_reference(floor, category, line, role, x=None, y=None, map_type=0, **extra):
        if floor is None or floor <= 0:
            return
        present = floor in by_floor
        status = "present" if present else "generated_floor" if floor in dynamic_floors else "unresolved"
        if map_type != 0:
            status = "non_fixed_map"
        entry = {"floor": floor, "category": category, "line": line, "role": role,
                 "x": x, "y": y, "map_type": map_type, "status": status, **extra}
        references.append(entry)
        if present and map_type == 0 and x is not None and y is not None:
            sizes = {(e["width"], e["height"]) for e in by_floor[floor]}
            if not any(0 <= x < w and 0 <= y < h for w, h in sizes):
                issue("maps", "coordinate_outside_map", **entry)

    for line, c in records(read(paths["warpfile"])):
        if len(c) >= 7:
            map_reference(number(c[1]), "warp", line, "source", number(c[2]), number(c[3]))
            map_reference(number(c[4]), "warp", line, "destination", number(c[5]), number(c[6]))

    npc_rows = list(records(read(paths["npcfile"])))
    script_paths = {p.name.casefold(): p for p in (server / "data/npc").iterdir() if p.is_file()}
    # Some item scripts live directly in data/, rather than data/npc/.
    for path in (server / "data").glob("*.txt"):
        script_paths.setdefault(path.name.casefold(), path)
    event_uses = collections.defaultdict(list)
    item_uses = collections.defaultdict(list)
    nested_uses = collections.defaultdict(list)
    tutors = collections.defaultdict(list)
    job_masters = collections.defaultdict(list)
    npc_types = collections.Counter()
    for line, c in npc_rows:
        if len(c) < 25:
            issue("tasks", "short_npc_record", line=line, columns=len(c))
            continue
        kind = label(c[0]).casefold()
        npc_types[kind] += 1
        floor, x, y = number(c[8]), number(c[9]), number(c[10])
        map_reference(floor, "npc", line, "placement", x, y, map_type=number(c[7]) or 0,
                      npc_type=kind, npc_name=label(c[1]), npc_id=number(c[3]))
        detail = {"line": line, "npc_id": number(c[3]), "name": label(c[1]), "floor": floor, "x": x, "y": y}
        if kind.startswith("skillmaster"):
            token = c[24].split(b"|", 1)[0]
            skill_id = number(token)
            if skill_id is not None:
                tutors[skill_id].append(detail)
        if kind.startswith("jobsmaster"):
            token = c[24].split(b"|", 1)[0]
            family = number(token)
            if family is not None:
                job_masters[family].append({**detail, "parameters": label(c[24])})
        for filename in re.findall(rb"[A-Za-z0-9_.-]+\.txt", c[24], flags=re.I):
            event_uses[filename.decode("ascii").casefold()].append({**detail, "npc_type": kind})

    # Include item-triggered scripts and their transitive file dependencies.
    # Matching a filename only establishes a dependency; it does not execute it.
    item_data = read(paths["itemfile"])
    for line, c in records(item_data):
        for filename in re.findall(rb"[A-Za-z0-9_.-]+\.txt", b"\t".join(c), flags=re.I):
            item_uses[filename.decode("ascii").casefold()].append({
                "line": line, "item_id": number(c[11]) if len(c) > 11 else None,
                "name": label(c[1]) if len(c) > 1 else ""})
    npc_script_count, item_script_count = len(event_uses), len(item_uses)
    pending = collections.deque(sorted(set(event_uses) | set(item_uses)))
    seen = set()
    script_data = {}
    while pending:
        filename = pending.popleft()
        if filename in seen:
            continue
        seen.add(filename)
        path = script_paths.get(filename)
        if not path:
            continue
        data = read(path)
        script_data[filename] = data
        for line, raw in enumerate(data.splitlines(), 1):
            raw = raw.split(b"//", 1)[0].strip()
            if not raw or raw.startswith(b"#"):
                continue
            for nested in re.findall(rb"[A-Za-z0-9_.-]+\.txt", raw, flags=re.I):
                target = nested.decode("ascii").casefold()
                if target != filename:
                    nested_uses[target].append({"path": path.relative_to(root).as_posix(), "line": line})
                    pending.append(target)

    tasks = []
    commands = collections.Counter()
    script_item_refs = []
    script_message_refs = []
    for filename in sorted(seen):
        uses = event_uses.get(filename, [])
        path = script_paths.get(filename)
        entry = {"script": filename, "present": path is not None, "npc_uses": uses,
                 "item_uses": item_uses.get(filename, []), "script_uses": nested_uses.get(filename, [])}
        if path:
            data = script_data[filename]
            entry.update(path=path.relative_to(root).as_posix(), bytes=len(data), sha256=sha256(data))
            for line, raw in enumerate(data.splitlines(), 1):
                raw = raw.split(b"//", 1)[0].strip()
                if not raw or raw.startswith(b"#"):
                    continue
                command = raw.split(None, 1)[0].lower()
                commands[label(command)] += 1
                match = re.match(rb"warp\s+(-?\d+)\s*,\s*(-?\d+)\s*,\s*(-?\d+)\s*,\s*(-?\d+)", raw, flags=re.I)
                if match:
                    map_type, floor, x, y = map(int, match.groups())
                    map_reference(floor, "npc_script", line, "warp", x, y, map_type, path=entry["path"])
                for item_match in re.finditer(rb"\b(?:Item|Give(?:Leak\d*)?Item|KillItem)\s+(\d+)", raw, re.I):
                    script_item_refs.append({"id": int(item_match[1]), "path": entry["path"], "line": line})
                message_match = re.match(rb"(?:EndWindow|Window|SysMsg)\s+(\d+)(?:\s|,|$)", raw, re.I)
                if message_match:
                    script_message_refs.append({"id": int(message_match[1]), "path": entry["path"], "line": line})
        else:
            issue("tasks", "missing_npc_script" if uses else "missing_item_or_nested_script",
                  script=filename, npc_uses=uses, item_uses=item_uses.get(filename, []), script_uses=nested_uses.get(filename, []))
        tasks.append(entry)

    tables = {}
    table_specs = {"skills": ("skillfile", 1), "techniques": ("techfile", 3),
                   "skill_job_limits": ("skilllvfile", 0), "jobs": ("jobsfile", 2),
                   "items": ("itemfile", 11)}
    for name, (key, id_column) in table_specs.items():
        rows = list(records(read(paths[key])))
        ids = collections.defaultdict(list)
        for line, c in rows:
            record_id = number(c[id_column]) if len(c) > id_column else None
            if record_id is None:
                issue(name, "invalid_id", line=line)
            else:
                ids[record_id].append((line, c))
        for record_id, entries in ids.items():
            if len(entries) > 1:
                issue(name, "duplicate_id", id=record_id, lines=[line for line, _ in entries])
        tables[name] = (rows, ids)

    # New pack rows have a known GBK encoding. Some short GBK names also form
    # valid UTF-8 bytes; do not guess their encoding from validity alone.
    gbk_ids = collections.defaultdict(set)
    pack_path = root / 'docs/jobskill_pack/manifest.json'
    if pack_path.exists():
        pack = json.loads(pack_path.read_text(encoding='utf-8'))
        for kind,key in [('skills','skillfile'),('techniques','techfile'),('jobs','jobsfile'),('items','itemfile')]:
            relative=paths[key].relative_to(root).as_posix()
            if inputs[relative]['sha256']!=pack['files'].get(relative,{}).get('after'): continue
            if kind=='skills': gbk_ids[kind]={s['id'] for s in pack['skills']}
            elif kind=='techniques': gbk_ids[kind]={i for s in pack['skills']+pack['extended_skills'] for i in s['techs']}
            elif kind=='jobs': gbk_ids[kind]={j['family']+rank for j in pack['jobs'] for rank in range(1,8)}
            else: gbk_ids[kind]={i['id'] for i in pack['items']}
    library_path=root/'docs/skill_library/manifest.json'
    if library_path.exists():
        library=json.loads(library_path.read_text(encoding='utf-8'))
        for kind,key in [('skills','skillfile'),('techniques','techfile')]:
            relative=paths[key].relative_to(root).as_posix()
            if inputs[relative]['sha256']==library['files'].get(relative,{}).get('after'):
                gbk_ids[kind].update(s['id'] for s in library['player_skills']) if kind=='skills' else gbk_ids[kind].update(t for s in library['player_skills'] for t in s['techs'])
    def table_label(kind,record_id,value):
        return value.decode('gbk') if record_id in gbk_ids[kind] else label(value)

    technique_by_skill = collections.defaultdict(list)
    for line, c in tables["techniques"][0]:
        if len(c) >= 7:
            skill_id = number(c[5])
            technique_by_skill[skill_id].append({"line": line, "id": number(c[3]), "name": table_label('techniques',number(c[3]),c[0]),
                                                "function": label(c[1]), "internal_level": number(c[6])})
    limits = collections.defaultdict(list)
    for line, c in tables["skill_job_limits"][0]:
        if len(c) >= 4:
            limits[number(c[1])].append({"line": line, "job": number(c[2]), "max_level": number(c[3])})

    skill_rows = []
    for skill_id, rows in sorted(tables["skills"][1].items()):
        line, c = rows[0]
        allowed = [r for r in limits[skill_id] if (r["max_level"] or 0) > 0]
        skill_rows.append({"id": skill_id, "name": table_label('skills',skill_id,c[0]), "line": line,
                           "technique_count": len(technique_by_skill[skill_id]),
                           "functions": sorted({r["function"] for r in technique_by_skill[skill_id]}),
                           "job_limit_rows": len(limits[skill_id]), "allowed_job_count": len(allowed),
                           "highest_job_limit": max((r["max_level"] for r in allowed), default=0),
                           "tutor_count": len(tutors[skill_id]), "tutors": tutors[skill_id]})
    # Orphan technique IDs can be monster-only/custom skills: flag, do not auto-create player skills.
    for skill_id, rows in technique_by_skill.items():
        if skill_id not in tables["skills"][1]:
            issue("skills", "technique_without_skill_definition", skill=skill_id, techniques=rows,
                  interpretation="candidate only; may be a monster/custom technique")
    for skill_id, uses in tutors.items():
        if skill_id not in tables["skills"][1]:
            issue("skills", "tutor_without_skill_definition", skill=skill_id, npc_uses=uses)

    job_rows = []
    limits_by_job = collections.defaultdict(list)
    for skill_id, rows in limits.items():
        for row in rows:
            if (row["max_level"] or 0) > 0:
                limits_by_job[row["job"]].append({"skill": skill_id, "max_level": row["max_level"]})
    for job_id, rows in sorted(tables["jobs"][1].items()):
        line, c = rows[0]
        family = job_id - job_id % 10
        job_rows.append({"id": job_id, "family": family, "rank": job_id % 10,
                         "name": table_label('jobs',job_id,c[0]), "line": line, "masters": job_masters[family],
                         "allowed_skills": limits_by_job[job_id]})
    for ref in script_item_refs:
        if ref["id"] not in tables["items"][1]:
            issue("tasks", "script_item_without_definition", **ref)
    messages_path = configured("msgtxtfile", "data/msg.txt")
    message_ids = {number(c[0]) for _, c in records(read(messages_path))}
    for ref in script_message_refs:
        if ref["id"] not in message_ids:
            issue("tasks", "script_message_without_definition", **ref)

    map_names = []
    names_path = server / "data/MapCompare.txt"
    if names_path.exists():
        for line, c in records(read(names_path)):
            if len(c) >= 2:
                map_names.append({"filename": label(c[0]), "name": label(c[1]), "line": line,
                                  "file_present": (paths["mapdir"] / label(c[0])).is_file()})

    unresolved = collections.defaultdict(list)
    for ref in references:
        if ref["status"] == "unresolved":
            unresolved[ref["floor"]].append(ref)
    missing_maps = [{"floor": floor, "references": refs, "reference_count": len(refs)}
                    for floor, refs in sorted(unresolved.items())]

    stats = {"native_map_files": len(maps), "unique_map_floors": len(by_floor),
             "extended_map_files": sum(e["variant"] == "LS2MAP extended" for e in maps),
             "client_map_cache_files": len(caches), "npc_records": len(npc_rows),
             "npc_script_files": sum(p.parent.name.casefold() == "npc" for p in script_paths.values()),
             "referenced_script_files": len(tasks),
             "npc_referenced_script_files": npc_script_count, "item_referenced_script_files": item_script_count,
             "missing_referenced_scripts": sum(not t["present"] for t in tasks),
             "unresolved_referenced_map_floors": len(missing_maps),
             **{name: {"records": len(rows), "unique_ids": len(ids)} for name, (rows, ids) in tables.items()}}
    report = {"generated_utc": datetime.now(timezone.utc).isoformat(), "root": str(root),
              "scope": "local dependency audit, pets excluded from writes; official 7.1 completeness unverified",
              "label_encoding": "UTF-8 if valid, otherwise GBK replacement decoding; original bytes preserved",
              "configured_paths": {k: str(p) for k, p in paths.items()}, "stats": stats,
              "npc_types": dict(npc_types), "script_commands": dict(commands),
              "missing_maps": missing_maps, "findings": findings, "inputs": inputs}
    dump_json(out / "audit.json", report)
    dump_json(out / "maps.json", maps)
    dump_json(out / "tasks.json", tasks)
    dump_json(out / "skills.json", skill_rows)
    dump_json(out / "jobs.json", job_rows)
    dump_json(out / "script_references.json", {"items": script_item_refs, "messages": script_message_refs})
    dump_json(out / "client_caches.json", caches)
    dump_csv(out / "maps.csv", maps, ["floor", "name", "width", "height", "variant", "path", "listed_in_startup_map_log", "sha256"])
    dump_csv(out / "map_references.csv", references, ["floor", "category", "line", "role", "map_type", "x", "y", "status", "path", "npc_name", "npc_id"])
    dump_csv(out / "skills.csv", skill_rows, ["id", "name", "line", "technique_count", "functions", "job_limit_rows", "allowed_job_count", "highest_job_limit", "tutor_count", "tutors"])
    dump_csv(out / "jobs.csv", job_rows, ["id", "family", "rank", "name", "line", "masters", "allowed_skills"])
    dump_csv(out / "map_name_index.csv", map_names, ["filename", "name", "line", "file_present"])
    dump_csv(out / "items.csv", [{"id": item_id, "unidentified_name": table_label('items',item_id,rows[0][1][0]),
                                  "name": table_label('items',item_id,rows[0][1][1]), "line": rows[0][0]}
                                 for item_id, rows in sorted(tables["items"][1].items())],
             ["id", "name", "unidentified_name", "line"])
    text = ["# CrossGate 内容盘点结果", "", "此报告检查本地依赖，不代表已补齐官方 7.1。详细编号、文件和哈希见同目录 JSON 与 CSV。", "", "## 基线", ""]
    text.extend(f"- {k}: {v}" for k, v in stats.items())
    text.extend(["", "## 待核查地图", "", "地图引用未解析时，可能缺少固定地图，也可能属于未识别的动态或条件路径，需要逐项确认。", ""])
    text.extend(f"- 地图 {m['floor']}：{m['reference_count']} 处引用。" for m in missing_maps)
    text.extend(["", "## 缺少参数脚本", ""])
    text.extend(f"- {t['script']}：{len(t['npc_uses'])} 个 NPC、{len(t['item_uses'])} 个道具、{len(t['script_uses'])} 处脚本引用。" for t in tasks if not t["present"])
    text.extend(["", "## 使用限制", "", "启动日志是磁盘快照，不证明当前进程已加载后续改动。地图层完整性检查不证明通行、出口或图档渲染正确。任务脚本存在不等于整个任务链可完成。怪物专用或定制 Tech 不会自动转为人物技能。", ""])
    (out / "report_zh.md").write_text("\n".join(text), encoding="utf-8")
    return stats


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--out", type=Path)
    args = parser.parse_args()
    output = args.out or args.root / "docs/cg71_content_audit"
    print(json.dumps(audit(args.root, output), ensure_ascii=False, indent=2))
