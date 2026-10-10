"""Stage, validate and install the shared task pack with scoped ID remapping.

Source archives are never modified. Existing DATA rows are retained verbatim.
All new content has provenance; unsupported source fragments are reported.
"""
from __future__ import annotations

import argparse
import collections
import copy
import hashlib
import json
import re
import shutil
import struct
from datetime import datetime, timezone
from pathlib import Path

import audit_content as core
from prepare_shared_task_sources import SOURCE, BATCH, OUT, ROOT

STAGE = BATCH / "staged"
DATA = ROOT / "gmsv/data"

# (primary-key column, minimum columns, new-ID allocation start, upper limit)
SPECS = {
    "itemset": (11, 102, 1000000, 2147483646),
    "enemybase": (1, 46, 2000000, 2147483646),
    "enemy": (2, 48, 3000000, 2147483646),
    "enemyai": (0, 41, 4000000, 2147483646),
    "group": (2, 35, 5000000, 2147483646),
    "encount": (0, 34, 6000000, 2147483646),
    "msg": (0, 2, 7000000, 2147483646),
    "dungeonconf": (3, 119, 8000000, 2147483646),
    "techarea": (1, 34, 9000000, 2147483646),
    "tech": (3, 15, 700000, 2147483646),
    "skill": (1, 19, 5000, 32766),
    "jobs": (2, 39, 6000, 32766),
    "jobsancestry": (1, 17, 6000, 32766),
    "skilllv": (0, 4, 1000000, 2147483646),
    "titlename": (0, 2, 12000, 65534),
    "itemrecipe": (1, 15, 1024, 2047),
    "itemmaterial": (1, 74, 1000, 65534),
    "enemytalk": (0, 26, 1000, 2147483646),
    "ship": (1, 35, 100, 32766),
    "harbor": (1, 8, 100, 32766),
    "npc": (3, 25, 10000000, 2147483646),
}
EXTRA_TABLES = {"warp", "effect", "titleconfig"}
ALL_TABLES = set(SPECS) | EXTRA_TABLES
TABLE_ALIASES = {"emeny": "enemy", "itemre": "itemrecipe", "itemrec": "itemrecipe", "dungeonconfig": "dungeonconf"}
COMMON = "的了是在我你不有这来去个一人要就说也都可会和为到上多很没能他她什么先好任务物品成功谢谢冒险者宠物道具获得需要任务等级我们你们东西这里不能时候" + "這來個說為沒會獲謝險寵須們東裡時麼種開與關"


def label(data):
    # All executable text has already been converted to the native GBK format.
    # Short GBK words can also form valid UTF-8 (for example 转), so guessing here
    # silently breaks Chinese script filenames.
    return data.decode("gbk", errors="replace")


def sha(data):
    return hashlib.sha256(data).hexdigest()


def save(path, obj):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(obj, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def decode_source(data):
    if data.startswith((b"\xff\xfe", b"\xfe\xff")):
        return data.decode("utf-16"), "utf-16"
    try:
        return data.decode("utf-8-sig"), "utf-8"
    except UnicodeDecodeError:
        pass
    choices = []
    for encoding in ["gbk", "cp950"]:
        text = data.decode(encoding, errors="replace")
        score = sum(text.count(c) for c in set(COMMON)) - text.count("\ufffd") * 30
        choices.append((score, encoding, text))
    selected = choices[1] if choices[1][0] > max(12, choices[0][0] * 1.7) else choices[0]
    return selected[2], selected[1]


def source_bytes(path, notes):
    original = path.read_bytes()
    text, encoding = decode_source(original)
    if "\ufffd" in text:
        notes.append({"kind": "text_decoding_replacement", "path": str(path), "encoding": encoding,
                      "count": text.count("\ufffd")})
    try:
        value = text.encode("gbk")
    except UnicodeEncodeError:
        value = text.encode("gbk", errors="replace")
        notes.append({"kind": "unrepresentable_gbk_character", "path": str(path), "encoding": encoding})
    if encoding not in {"gbk", "utf-8"} or original.startswith(b"\xef\xbb\xbf"):
        notes.append({"kind": "import_text_transcoded", "path": str(path), "encoding": encoding})
    return value


def active_lines(data):
    for no, raw in enumerate(data.replace(b"\r\n", b"\n").replace(b"\r", b"\n").split(b"\n"), 1):
        if raw.strip() and not raw.lstrip().startswith((b"#", b"//")):
            yield no, raw


def table_kind(path):
    stem = path.stem.casefold()
    return TABLE_ALIASES.get(stem, stem) if stem in ALL_TABLES or stem in TABLE_ALIASES else None


def repair_script_syntax(data, path, notes):
    typos={'bock':'Block','blcok':'Block','bolck':'Block','window_okitem':'Window_OK Item','wndwindow':'EndWindow','enwindow':'EndWindow',
           'endiwndow':'EndWindow','endowindow':'EndWindow','endwindoe':'EndWindow',
           'endwindw':'EndWindow','endwwindow':'EndWindow','winodw_no':'Window_No',
           'wwindow_ok':'Window_Ok','windoe_yes':'Window_Yes','leavegruop':'LeaveGroup'}
    result=[]
    for ln,raw in enumerate(data.replace(b'\r\n',b'\n').replace(b'\r',b'\n').split(b'\n'),1):
        before=raw
        m=re.match(rb'^(\s*)([A-Za-z_]+)(.*)$',raw)
        if m:
            token=m[2].decode().lower()
            if token in typos:raw=m[1]+typos[token].encode()+m[3]
            raw=re.sub(rb'(?i)^(\s*)(Block|Window_Yes|Window_Ok|Window_No)(?=(?:EndEvent|NowEvent|Item|Gold))',rb'\1\2 ',raw)
            raw=re.sub(rb'(?i)^(\s*)(Give|Kill)\s+Item\b',rb'\1\2Item',raw)
        if raw!=before:notes.append({'kind':'source_script_token_typo_repaired','path':str(path),'line':ln,'before':label(before),'after':label(raw)})
        result.append(raw)
    return b'\r\n'.join(result)


class Builder:
    def __init__(self):
        self.notes = []
        self.missing = []
        self.units = []
        self.owner = {}
        self.entities = {k: [] for k in SPECS}
        self.local = collections.defaultdict(list)
        self.pool = collections.defaultdict(list)
        self.by_signature = {}
        self.base = {}
        self.used = {}
        self.cursor = {}
        self.additions = collections.defaultdict(list)
        self.files = {}
        self.transformed = {}
        self.map_entities = []
        self.maps_by_original = collections.defaultdict(list)
        self.map_local = collections.defaultdict(list)
        self.script_local = collections.defaultdict(list)
        self.script_global = collections.defaultdict(list)
        self.flags = {}
        self.reference_aliases={}
        self.flag_providers = collections.defaultdict(list)
        self.stage_originals = {}
        self.units_by_root = {}
        self.job_families = {}
        self.context_rows = {}
        self.tile_info = {}
        for _, c in core.records((DATA / 'map/newmapset.txt').read_bytes().replace(b' ', b'\t')):
            c = [x for x in c if x]
            if len(c) >= 5 and c[0].isdigit(): self.tile_info[int(c[0])] = c
        for kind, (key, width, start, limit) in SPECS.items():
            path = DATA / (kind + ".txt")
            raw = path.read_bytes() if path.exists() else b""
            self.stage_originals[kind + ".txt"] = raw
            self.base[kind] = {}
            for line, cols in core.records(raw):
                if len(cols) > key and core.number(cols[key]) is not None:
                    self.base[kind].setdefault(core.number(cols[key]), cols)
            self.used[kind] = set(self.base[kind])
            self.cursor[kind] = start
        for name in EXTRA_TABLES:
            self.stage_originals[name + ".txt"] = (DATA / (name + ".txt")).read_bytes()
        self.base_cap_pairs={tuple(c[1:3]) for c in self.base['skilllv'].values() if len(c)>3}
        self.base_maps = {}
        for p in (DATA / "map").iterdir():
            if p.is_file() and p.open("rb").read(6) == b"LS2MAP":
                b = p.read_bytes()
                m = core.native_map(b)
                m["source"] = str(p)
                m["geometry"] = sha(struct.pack(">HH", m["width"], m["height"]) + b[m["header_bytes"]:])
                self.base_maps[m["floor"]] = m
        self.used_maps = set(self.base_maps)
        # Generated dungeon floors and all existing references remain reserved.
        for raw in self.stage_originals["dungeonconf.txt"].splitlines():
            c = raw.split(b"\t")
            if len(c) > 49 and core.number(c[49]) is not None:
                self.used_maps.add(core.number(c[49]))
        self.map_cursor = 45000
        self.npc_cursor = 10000000
        self.warp_cursor = max(int(c[0]) for _, c in core.records(self.stage_originals["warp.txt"])) + 1

    def scan(self):
        nested = json.loads((OUT / "nested_sources.json").read_text(encoding="utf-8"))
        sources = [(SOURCE, "outer", "全部任务共享")]
        sources += [(Path(a["stage"]), f"nested:{i}", Path(a["relative_source"]).stem)
                    for i, a in enumerate(nested["archives"]) if "error" not in a]
        for source, prefix, archive_name in sources:
            files = sorted(p for p in source.rglob("*") if p.is_file())
            roots = {p.parent for p in files if table_kind(p)}
            roots |= {p.parent.parent for p in files if p.parent.name.casefold() in {"npc", "map"}}
            if prefix != "outer" and not roots:
                common = source
                while common.is_dir():
                    children = list(common.iterdir())
                    if len(children) == 1 and children[0].is_dir():
                        common = children[0]
                    else:
                        break
                roots.add(common)
            for root in sorted(roots):
                unit = {"id": len(self.units), "root": str(root), "source_group": prefix,
                        "name": root.relative_to(SOURCE).as_posix() if prefix == "outer" else archive_name + "/" + root.relative_to(source).as_posix(),
                        "tables": collections.defaultdict(list), "scripts": [], "maps": [], "other_files": []}
                self.units.append(unit)
                self.units_by_root[root] = unit
            for path in files:
                parents = [r for r in roots if path.is_relative_to(r)]
                if not parents:
                    continue
                unit = self.units_by_root[max(parents, key=lambda r: len(r.parts))]
                self.owner[path] = unit["id"]
                kind = table_kind(path)
                data = path.read_bytes()
                if data.startswith(b"LS2MAP"):
                    self.read_map(unit, path, data)
                elif kind:
                    data = source_bytes(path, self.notes)
                    for ln, raw in active_lines(data):
                        c = raw.split(b"\t")
                        if kind in SPECS:
                            key, width, *_ = SPECS[kind]
                            if len(c) <= key or core.number(c[key]) is None:
                                self.notes.append({"kind": "ignored_table_annotation", "path": str(path), "line": ln,
                                                   "text": label(raw)[:160]})
                                continue
                            if len(c) > width and not any(c[width:]):
                                c = c[:width]
                            # Some source tables omit optional final empty fields.
                            if kind == "enemybase" and 36 <= len(c) < width:
                                self.notes.append({"kind": "optional_monster_tech_slots_padded", "path": str(path), "line": ln, "columns": len(c)})
                                c += [b""] * (width - len(c))
                            if kind == "enemy" and len(c) == 73 and not any(c[48:68]):
                                self.notes.append({"kind": "legacy_enemy_extension_preserved_in_source", "path": str(path), "line": ln})
                                c = c[:48]
                            if kind == "npc" and len(c) == 26 and c[8:10] == [b"", b""]:
                                del c[8]
                                self.notes.append({"kind": "duplicate_empty_npc_column_removed", "path": str(path), "line": ln})
                            if kind=='group' and len(c)==33 and path.parent.name=='迟到的清明节任务' and c[2]==b'900110':
                                c[13:13]=[b'0',b'0']
                                self.notes.append({'kind':'missing_final_enemy_slots_repaired','path':str(path),'line':ln,'slots':[8,9]})
                            if kind in {"group", "encount", "enemyai", "techarea"} and len(c) >= (24 if kind in {"group", "encount"} else width-3) and len(c) < width:
                                self.notes.append({"kind": "optional_data_columns_padded", "table": kind, "path": str(path), "line": ln, "columns": len(c)})
                                c += [b""] * (width - len(c))
                            if len(c) < width and len(c) >= width - 3:
                                c += [b""] * (width - len(c))
                            if len(c) != width and kind not in {"msg", "group", "encount", "enemyai", "techarea", "titlename"}:
                                self.missing.append({"unit": unit["id"], "kind": "table_shape", "table": kind,
                                                     "path": str(path), "line": ln, "columns": len(c), "expected": width})
                        elif kind == "npc" and (len(c) < 25 or c[0].strip().startswith(b"#")):
                            continue
                        elif kind == "warp" and (len(c) != 7 or not all(core.number(x) is not None for x in c)):
                            continue
                        unit["tables"][kind].append({"columns": c, "path": str(path), "line": ln})
                elif path.suffix.casefold() in {".txt", ".bus"}:
                    data = source_bytes(path, self.notes)
                    # Small submissions often put several DATA tables in one readme.
                    embedded = False
                    section = None
                    for ln, raw in enumerate(data.replace(b"\r\n", b"\n").split(b"\n"), 1):
                        marker = re.search(rb"\b(" + b"|".join(k.encode() for k in ALL_TABLES) + rb")\s*\.txt\b", raw, re.I)
                        if not marker and b"\t" not in raw:
                            marker = re.search(rb"^\s*#?\s*(" + b"|".join(k.encode() for k in ALL_TABLES) + rb")(?=\s*[\x80-\xff])", raw, re.I)
                        if marker and b"\t" not in raw:
                            section = marker[1].decode().lower()
                            continue
                        if not raw.strip() or raw.lstrip().startswith((b"#", b"//")):
                            continue
                        if section and b"\t" in raw:
                            c = raw.split(b"\t")
                            if section == "npc" and len(c) >= 25 or section in SPECS and len(c) > SPECS[section][0] and core.number(c[SPECS[section][0]]) is not None:
                                width = 25 if section == "npc" else SPECS[section][1]
                                if len(c) > width and not any(c[width:]):
                                    c = c[:width]
                                if section == "enemybase" and 36 <= len(c) < width:
                                    self.notes.append({"kind": "optional_monster_tech_slots_padded", "path": str(path), "line": ln, "columns": len(c)})
                                    c += [b""] * (width - len(c))
                                if section == "enemy" and 37 <= len(c) < width:
                                    self.notes.append({"kind": "legacy_enemy_optional_columns_padded", "path": str(path), "line": ln, "columns": len(c)})
                                    c += [b""] * (width - len(c))
                                if section == "encount" and 24 <= len(c) < width:
                                    self.notes.append({"kind": "optional_encounter_columns_padded", "path": str(path), "line": ln, "columns": len(c)})
                                    c += [b""] * (width - len(c))
                                if section == "msg" and len(c) > 2:
                                    c = c[:2] if all(core.number(v) is not None or not v for v in c[2:]) else [c[0], b" ".join(c[1:])]
                                if len(c) != width:
                                    self.missing.append({"unit": unit["id"], "kind": "embedded_table_shape", "table": section, "path": str(path), "line": ln, "columns": len(c), "expected": width})
                                    continue
                                unit["tables"][section].append({"columns": c, "path": str(path), "line": ln})
                                embedded = True
                            elif section == "warp" and len(c) == 7 and all(core.number(v) is not None for v in c):
                                unit["tables"][section].append({"columns": c, "path": str(path), "line": ln})
                                embedded = True
                        elif section == "titleconfig" and b"TITLE=" in raw.upper():
                            unit["tables"][section].append({"columns": [raw], "path": str(path), "line": ln})
                            embedded = True
                    script_like = bool(re.search(rb"(?im)^\s*(?:block|window|endwindow|encount|warp|giveitem)\b", data))
                    if path.parent.name.casefold() == "npc" or script_like or path.suffix.casefold() == ".bus":
                        if path.suffix.casefold() == ".bus":
                            unit["other_files"].append({"path": str(path), "kind": "bus", "data": data})
                        elif not embedded:
                            data = repair_script_syntax(data,path,self.notes)
                            alias = "stp_" + sha(str(path).encode("utf-8"))[:18] + ".txt"
                            record = {"path": str(path), "alias": alias, "data": data, "unit": unit["id"]}
                            unit["scripts"].append(record)
                            self.script_local[(unit["id"], path.name.casefold())].append(record)
                            self.script_global[path.name.casefold()].append(record)
                    else:
                        unit["other_files"].append({"path": str(path), "kind": "document"})
        self.units = [u for u in self.units if u["tables"] or u["maps"] or u["scripts"] or any(x["kind"] == "bus" for x in u["other_files"])]
        self.unit_by_id = {u["id"]: u for u in self.units}
        self.context_rows = {r['path']+':'+str(r['line']):r['columns'] for u in self.units for rows in u['tables'].values() for r in rows}

    def read_map(self, unit, path, data):
        try:
            m = core.native_map(data)
        except ValueError as error:
            w, h = struct.unpack_from(">HH", data, 40)
            if len(data) >= 60 and data[6:8] == b"\xff\xff" and len(data) in {44 + w*h*4, 60 + w*h*4}:
                floor = struct.unpack_from(">I", data, 48)[0]
                if floor < 65535:
                    header = bytearray(data[:44]); struct.pack_into(">H", header, 6, floor)
                    missing = 60 + w*h*4 - len(data)
                    data = bytes(header) + b"\0" * missing + data[60:]
                    m = core.native_map(data)
                    self.notes.append({"kind": "extended_header_four_byte_map_normalized", "unit": unit["id"], "path": str(path), "floor": floor, "missing_payload_bytes_zero_filled": missing})
                else:
                    self.missing.append({"unit": unit["id"], "kind": "unsupported_map", "path": str(path), "error": str(error)})
                    return
            else:
                self.missing.append({"unit": unit["id"], "kind": "unsupported_map", "path": str(path), "error": str(error)})
                return
        named_id = re.match(r"^(\d+)(?:\D|$)", path.name)
        if named_id and int(named_id[1]) != m["floor"]:
            m["filename_floor"] = int(named_id[1])
        m.update(unit=unit["id"], source=str(path), data=data,
                 geometry=sha(struct.pack(">HH", m["width"], m["height"]) + data[m["header_bytes"]:]))
        unit["maps"].append(m)

    def allocate(self, kind, preferred=None):
        _, _, start, limit = SPECS[kind]
        if preferred is not None and 0 <= preferred <= limit and preferred not in self.used[kind]:
            value = preferred
        else:
            value = self.cursor[kind]
            while value in self.used[kind]:
                value += 1
            if value > limit:
                raise ValueError(f"{kind} ID capacity exhausted")
            self.cursor[kind] = value + 1
        self.used[kind].add(value)
        return value

    def repair_map_ids(self):
        for u in self.units:
            refs = set()
            def add(value, map_type=b"0"):
                if core.number(map_type) == 0 and core.number(value) is not None:
                    refs.add(int(value))
            for kind, rows in u["tables"].items():
                for row in rows:
                    c = row["columns"]
                    if kind == "npc" and len(c) >= 25:
                        add(c[8], c[7])
                        if c[0].lower() == b"warp":
                            p = c[24].split(b"|")
                            if len(p) >= 2: add(p[1], p[0])
                        if c[0].lower() == b"standenemy":
                            p = c[24].split(b"|")
                            q = p[1].split(b",") if len(p) > 1 else []
                            if len(q) >= 2: add(q[1], q[0])
                    elif kind == "warp" and len(c) == 7:
                        add(c[1]); add(c[4])
                    elif kind == "encount" and len(c) > 3: add(c[3], c[2])
                    elif kind == "dungeonconf" and len(c) > 15:
                        add(c[9], c[8]); add(c[15], c[14])
                    elif kind == "techarea" and len(c) > 6: add(c[6], c[5])
            for s in u["scripts"]:
                for m in re.finditer(rb"\bWarp\s*,?\s*(-?\d+)\s*,\s*(-?\d+)", s["data"], re.I):
                    add(m[2], m[1])
            filenames = collections.Counter(m.get("filename_floor", m["floor"]) for m in u["maps"])
            for m in u["maps"]:
                named = m.get("filename_floor")
                if named is not None:
                    # A renamed copy may retain its original header; duplicated or
                    # unreferenced filenames are only labels, never authoritative IDs.
                    change = named in refs and m["floor"] not in refs and filenames[named] == 1
                    old = m["floor"]
                    if change:
                        m["header_floor"] = old; m["floor"] = named
                    self.notes.append({"kind": "map_filename_header_disagreement", "unit": u["id"], "path": m["source"],
                                       "header_floor": old, "filename_floor": named, "selected_floor": m["floor"],
                                       "reason": "unique referenced renamed copy" if change else "internal header retained"})

    def register(self):
        self.repair_map_ids()
        self.repair_missing_graphics()
        reserved_families = {j-j%10 for j in self.used["jobs"]} | self.used["jobsancestry"]
        for u in self.units:
            families = sorted({int(r["columns"][2])//10*10 for r in u["tables"].get("jobs", [])})
            for family in families:
                new_family = family
                if new_family in reserved_families:
                    new_family = 6000
                    while new_family in reserved_families: new_family += 10
                reserved_families.add(new_family)
                self.job_families[(u["id"], family)] = new_family
            for family in families:
                if any(int(r["columns"][1]) == family for r in u["tables"].get("jobsancestry", [])): continue
                original = self.base["jobsancestry"].get(family) or self.base['jobsancestry'][140]
                c = original.copy(); c[1] = str(family).encode()
                jobs = {int(r["columns"][2])%10:int(r["columns"][2]) for r in u["tables"]["jobs"] if int(r["columns"][2])//10*10 == family}
                for rank in range(1, 8): c[1+rank] = str(jobs.get(rank, -1)).encode()
                c[0] = next(r["columns"][0] for r in u["tables"]["jobs"] if int(r["columns"][2])//10*10 == family)
                u["tables"]["jobsancestry"].append({"columns": c, "path": u["root"] + "/[derived-job-ancestry]", "line": 0})
                self.notes.append({"kind": "supplied_job_family_ancestry_completed", "unit": u["id"], "family": family, "new_family": self.job_families[(u["id"], family)]})
            if not u["tables"].get("skilllv"):
                local_jobs = {int(r["columns"][2]) for r in u["tables"].get("jobs", [])}
                for ln, c in core.records(self.stage_originals["skilllv.txt"]):
                    if len(c) == 4 and core.number(c[2]) in local_jobs:
                        u["tables"]["skilllv"].append({"columns": c.copy(), "path": str(DATA / "skilllv.txt") + "[inherited]", "line": ln})
        # Reserve every original source map ID before allocating alternate variants.
        self.used_maps |= {m["floor"] for u in self.units for m in u["maps"]}
        geometry = {}
        original_available = set(self.base_maps)
        for u in self.units:
            for m in u["maps"]:
                key = (m["floor"], m["geometry"])
                existing = self.base_maps.get(m["floor"])
                if existing and existing["geometry"] == m["geometry"]:
                    new = m["floor"]
                elif key in geometry:
                    new = geometry[key]
                elif m["floor"] not in original_available and (m["floor"] < 65535 or m["variant"] == "LS2MAP extended"):
                    new = m["floor"]
                    original_available.add(new)
                else:
                    while self.map_cursor in self.used_maps:
                        self.map_cursor += 1
                    if self.map_cursor >= 65535:
                        raise ValueError("16-bit alternate map space exhausted")
                    new = self.map_cursor
                    self.used_maps.add(new)
                geometry[key] = new
                m["new_id"] = new
                self.map_local[(u["id"], m["floor"])].append(m)
                self.maps_by_original[m["floor"]].append(m)
                if not existing or existing["geometry"] != m["geometry"]:
                    if not any(x["new_id"] == new for x in self.map_entities):
                        self.map_entities.append(m)
        for u in self.units:
            for kind, records in u["tables"].items():
                if kind not in SPECS or kind == "skilllv":
                    continue
                keycol = SPECS[kind][0]
                for source in records:
                    c = source["columns"]
                    if len(c) <= keycol or core.number(c[keycol]) is None:
                        continue
                    old = int(c[keycol])
                    signature = (kind, u["id"], old, tuple(c))
                    entity = self.by_signature.get(signature)
                    if entity is None:
                        same = False  # A supplied definition belongs to its task namespace.
                        if kind == "jobs":
                            new = self.job_families[(u["id"], old//10*10)] + old%10
                            if new in self.used[kind]: raise ValueError("duplicate rank in supplied job family")
                            self.used[kind].add(new)
                        elif kind == "jobsancestry":
                            new = self.job_families[(u["id"], old)] if (u["id"], old) in self.job_families else self.allocate(kind, old)
                            self.used[kind].add(new)
                        elif kind=='itemrecipe':new=self.allocate(kind)
                        else:
                            new = old if same else self.allocate(kind, old)
                        entity = {"kind": kind, "old_id": old, "new_id": new, "columns": c,
                                  "path": source["path"], "line": source["line"], "units": [], "reuse_base": same}
                        self.by_signature[signature] = entity
                        self.entities[kind].append(entity)
                        self.pool[(kind, old)].append(entity)
                    entity["units"].append(u["id"])
                    self.local[(u["id"], kind, old)].append(entity)
        # Source flag numbers are scoped to the owning quest, including chapters.
        baseline = b"\n".join(p.read_bytes() for p in (DATA / "npc").iterdir() if p.is_file())
        baseline += self.stage_originals["titleconfig.txt"]
        # Lua modules can use the same native event bits as legacy DATA scripts.
        lua = b'\n'.join(p.read_bytes() for p in (ROOT / 'gmsv/lua').rglob('*.lua'))
        used_flags = {k: {int(m[1]) for m in re.finditer(rb"\b" + k.encode() + rb"\s*(\d+)", baseline, re.I)}
                      for k in ["endevent", "nowevent", "globalflag"]}
        for kind in used_flags:
            used_flags[kind] |= {int(m[1]) for m in re.finditer(kind.encode() + rb'\s*\([^,\r\n]+,\s*(\d+)', lua, re.I)}
        for u in self.units:
            corpus = b"\n".join(s["data"] for s in u["scripts"])
            for kind, cap, first in [("endevent", 1024, 512), ("nowevent", 1024, 512), ("globalflag", 512, 256)]:
                assigned = sorted({int(m[1]) for m in re.finditer(rb"(?im)^\s*" + kind.encode() + rb"\s*(\d+)\s*=(?!=)", corpus)})
                for old in assigned:
                    campaign = self.campaign(u["id"])
                    earlier = [(owner, new) for owner, new in self.flag_providers.get((kind, old), []) if self.campaign(owner) == campaign]
                    if earlier:
                        self.flags[(u["id"], kind, old)] = earlier[0][1]
                        self.flag_providers[(kind, old)].append((u["id"], earlier[0][1]))
                        continue
                    new = first
                    while new in used_flags[kind]:
                        new += 1
                    if new >= cap:
                        self.missing.append({"unit": u["id"], "kind": "flag_capacity", "flag_kind": kind, "old_id": old})
                        continue
                    used_flags[kind].add(new)
                    self.flags[(u["id"], kind, old)] = new
                    self.flag_providers[(kind, old)].append((u["id"], new))

    def campaign(self, unit):
        parts = Path(self.unit_by_id[unit]["root"]).parts
        for i, part in enumerate(parts):
            if part.endswith("资料片"):
                # The same supplied expansion appears both under 待修复 and as
                # a second extracted copy; its chapter event state is shared.
                return tuple(parts[i: i+1])
        for i, part in enumerate(parts):
            if part in {'任务整理','小任务'} and i+1<len(parts):
                return tuple(parts[i:i+2])
        return self.unit_by_id[unit]["root"]

    def repair_missing_graphics(self):
        """Use installed art for unavailable tiles, recording each custom change."""
        # The native reader promotes legacy tile 25269 to serial 225269.
        # Verified with Map.GetImage against the untouched isolated runtime.
        # Both direct serials and this installed legacy bank are valid.
        known = set(self.tile_info) | {v-200000 for v in self.tile_info if 200000<=v<=265535}
        for u in self.units:
            for m in u['maps']:
                if m['variant'] != 'LS2MAP': continue
                n = m['width'] * m['height']
                ground = list(struct.unpack_from('>' + str(n) + 'H', m['data'], 44))
                objects = list(struct.unpack_from('>' + str(n) + 'H', m['data'], 44 + n*2))
                unknown = set(ground + objects) - known
                if not unknown: continue
                walkable = collections.Counter(v for v in ground if v and v in known and self.tile_info.get(v,self.tile_info.get(v+200000,[]))[1:4] == [b'1',b'1',b'1'])
                replacement = walkable.most_common(1)[0][0] if walkable else 1003
                changed_ground = collections.Counter(v for v in ground if v in unknown)
                changed_object = collections.Counter(v for v in objects if v in unknown)
                ground = [replacement if v in unknown else v for v in ground]
                # An unrenderable object remains an obstacle, rather than silently
                # opening paths through gates. Entry points are checked separately.
                objects = [13081 if v in unknown else v for v in objects]
                m['data'] = m['data'][:44] + struct.pack('>'+str(n)+'H',*ground) + struct.pack('>'+str(n)+'H',*objects)
                m['geometry'] = sha(struct.pack('>HH',m['width'],m['height'])+m['data'][44:])
                m['custom_graphics_adapter'] = True
                self.notes.append({'kind':'custom_map_missing_art_adapter','unit':u['id'],'path':m['source'],
                                   'ground_replacement':replacement,'object_replacement':13081,
                                   'ground_counts':dict(changed_ground),'object_counts':dict(changed_object)})

    def related(self, candidates, unit, context=""):
        if len(candidates) <= 1:
            return candidates
        root = Path(self.unit_by_id[unit]["root"])
        source_context = Path(context.rsplit(":", 1)[0]).parent if context else root
        common = []
        for item in candidates:
            owners = item.get("units", [item.get("unit")])
            scores = []
            for owner in owners:
                score = 0
                if owner in self.unit_by_id:
                    for a, b in zip(root.parts, Path(self.unit_by_id[owner]["root"]).parts):
                        if a != b: break
                        score += 1
                scores.append(score)
            score = max(scores) * 100
            path = item.get("path", item.get("source"))
            if path:
                for a, b in zip(source_context.parts, Path(path).parent.parts):
                    if a != b: break
                    score += 1
            common.append((score, item))
        best = max(x[0] for x in common)
        return [x[1] for x in common if x[0] == best]

    def resolve(self, unit, kind, value, context="", optional=False):
        number = core.number(value)
        if number is None or number < 0:
            return value
        alias=self.reference_aliases.get((unit,kind,number))
        if alias is not None:return self.resolve(unit,kind,str(alias).encode(),context,optional)
        local = self.local.get((unit, kind, number), [])
        candidates = self.related(local, unit, context)
        if not candidates and number in self.base[kind]:
            return str(number).encode()
        if not candidates:
            candidates = self.related(self.pool.get((kind, number), []), unit, context)
        ids = {x["new_id"] for x in candidates}
        if len(ids) == 1:
            return str(next(iter(ids))).encode()
        if len(ids) > 1 and len({tuple(x["columns"]) for x in candidates}) == 1:
            chosen = min(candidates, key=lambda x: (x["path"], x["line"]))
            self.notes.append({"kind": "equivalent_source_definition_selected", "unit": unit, "table": kind, "old_id": number, "new_id": chosen["new_id"], "context": context})
            return str(chosen["new_id"]).encode()
        if len(ids)>1:
            # Different archive copies can define the same number differently.
            # All definitions remain uniquely numbered; tie this external
            # reference to one deterministic, documented local adaptation.
            context_row=self.context_rows.get(context,[])
            names=[label(v).strip() for v in context_row[:2] if len(label(v).strip())>1 and not label(v).strip().isdigit()]
            def affinity(e):
                body=label(e['columns'][1] if kind=='msg' and len(e['columns'])>1 else e['columns'][0])
                return sum(len(n) for n in names if n in body)
            chosen=min(candidates,key=lambda e:(-affinity(e),e['path'],e['line'],e['new_id']))
            self.notes.append({'kind':'custom_ambiguous_reference_binding','unit':unit,'table':kind,'old_id':number,
                               'selected':chosen['new_id'],'alternatives':sorted(ids),'context':context,'source':chosen['path']})
            return str(chosen['new_id']).encode()
        if not candidates and number in self.base[kind]:
            return str(number).encode()
        if optional and number == 0:
            return value
        if not candidates:
            if kind=='tech' and number>=1000:
                family=number//100*100
                rows=[(id,c) for id,c in self.base['tech'].items() if family<=id<family+100 and core.number(c[6]) is not None and 1<=int(c[6])<=10]
                if rows and len({(c[1],c[5]) for id,c in rows})==1:
                    new,c=max(rows,key=lambda x:(int(x[1][6]),-abs(x[0]-number)))
                    self.notes.append({'kind':'custom_unsupported_tech_tier_adapter','unit':unit,'from':number,'to':new,'name':label(c[0]),'context':context})
                    return str(new).encode()
            # An extra zero occurs in several submitted encounter/group IDs.
            corrected = {int(str(number)[:i] + str(number)[i+1:]) for i, ch in enumerate(str(number))
                         if ch == "0" and len(str(number)) > 1}
            fixes = [(old, self.local[(unit, kind, old)]) for old in corrected if self.local.get((unit, kind, old))]
            if len(fixes) == 1:
                old, rows = fixes[0]
                new = int(self.resolve(unit,kind,str(old).encode(),context))
                self.notes.append({"kind": "extra_zero_reference_repair", "unit": unit, "table": kind,
                                   "from": number, "source_id": old, "to": new, "context": context})
                return str(new).encode()
        self.missing.append({"unit": unit, "kind": "unresolved_reference" if not ids else "ambiguous_reference",
                             "table": kind, "id": number, "candidates": sorted(ids), "context": context})
        return value

    def floor(self, unit, value, map_type=0, context=""):
        n = core.number(value)
        if n is None or n <= 0:
            return value
        if n == 777:
            return value  # Native generated-dungeon NPC/encounter template sentinel.
        if map_type in {1, 2}:
            return self.resolve(unit, "dungeonconf", value, context)
        if map_type != 0:
            return value
        matches = self.related(self.map_local.get((unit, n), []), unit, context)
        if not matches and n in self.base_maps:
            return value
        if not matches:
            matches = self.related(self.maps_by_original.get(n, []), unit, context)
        ids = {m["new_id"] for m in matches}
        if len(ids) == 1:
            return str(next(iter(ids))).encode()
        if len(ids)>1:
            c=self.context_rows.get(context,[])
            points=[]
            if len(c)>=25 and core.number(c[8])==n:
                points=[(core.number(c[i]),core.number(c[i+1])) for i in range(9,17,2)]
            fits=[m for m in matches if all(x is not None and y is not None and 0<=x<m['width'] and 0<=y<m['height'] for x,y in points)]
            chosen=min(fits or matches,key=lambda m:(m['new_id']!=n,m['source']))
            self.notes.append({'kind':'custom_ambiguous_map_binding','unit':unit,'floor':n,'selected':chosen['new_id'],
                               'alternatives':sorted(ids),'context':context,'source':chosen['source']})
            return str(chosen['new_id']).encode()
        if not matches and n in self.base_maps:
            return value
        self.missing.append({"unit": unit, "kind": "missing_map" if not ids else "ambiguous_map", "floor": n,
                             "candidates": sorted(ids), "context": context})
        return value

    def flag(self, unit, kind, old):
        key = (unit, kind, int(old))
        if key in self.flags:
            return self.flags[key]
        candidates = self.flag_providers.get((kind, int(old)), [])
        related = [c for c in candidates if self.campaign(c[0]) == self.campaign(unit)]
        values = {c[1] for c in related}
        if len(values) == 1:
            return next(iter(values))
        return int(old)

    def filename(self, unit, raw, context=""):
        name = label(raw).casefold()
        candidates = self.related(self.script_local.get((unit, name), []), unit, context)
        if not candidates:
            candidates = self.related(self.script_global.get(name, []), unit, context)
        if not candidates and name[:1].isascii():
            # A duplicated/pasted prefix in a DATA field does not change the
            # actual script filename. Only accept an exact existing suffix.
            fixes = {name[i:] for i in [1,2,3] if len(name)>i and name[i:] in self.script_global}
            if len(fixes)==1:
                fixed=next(iter(fixes))
                candidates=self.related(self.script_global[fixed],unit,context)
                self.notes.append({'kind':'duplicated_script_prefix_repaired','unit':unit,'from':label(raw),'to':fixed,'context':context})
        if not candidates:
            normalized=re.sub(r'[_\-\s]','',name)
            numbers=re.findall(r'\d+',name)
            fixes=[k for k in self.script_global if re.sub(r'[_\-\s]','',k)==normalized and re.findall(r'\d+',k)==numbers]
            if len(fixes)==1:
                candidates=self.related(self.script_global[fixes[0]],unit,context)
                self.notes.append({'kind':'script_separator_typo_repaired','unit':unit,'from':label(raw),'to':fixes[0],'context':context})
        if not candidates:
            authors=r'^(?:cayenne|jj|gcayenne|jcayenne|gg_cayenne|xy_zzp|xy|xx|zzy|zz|xg|get|an)[_-]'
            def stem(k):return re.sub(r'[_\-\s]','',re.sub(authors,'',k))
            fixes=[k for k in self.script_global if stem(k)==stem(name) and re.findall(r'\d+',k)==re.findall(r'\d+',name)]
            if len(set(fixes))==1:
                fixed=fixes[0];candidates=self.related(self.script_global[fixed],unit,context)
                self.notes.append({'kind':'script_author_prefix_alias_repaired','unit':unit,'from':label(raw),'to':fixed,'context':context})
        unique = {s["alias"] for s in candidates}
        if len(unique)>1 and len({sha(s['data']) for s in candidates})==1:
            selected=min(candidates,key=lambda s:s['path']);unique={selected['alias']}
            self.notes.append({'kind':'equivalent_script_copy_selected','unit':unit,'script':name,'selected':selected['path']})
        if len(unique) == 1:
            return next(iter(unique)).encode()
        if not candidates and (DATA / "npc" / label(raw)).is_file():
            return raw
        self.missing.append({"unit": unit, "kind": "missing_script" if not unique else "ambiguous_script",
                             "script": label(raw), "context": context})
        return raw

    def filenames(self, unit, data, context=""):
        return re.sub(rb"[^\s|,\";=()]+\.txt\b", lambda m: self.filename(unit, m[0], context), data, flags=re.I)

    def coord_tuple(self, unit, value, context):
        parts = value.split(b",")
        if len(parts) >= 4 and all(core.number(x) is not None for x in parts[:4]):
            parts[1] = self.floor(unit, parts[1], int(parts[0]), context)
            parts[2],parts[3]=self.fit_position(parts[1],parts[2],parts[3],int(parts[0]),context)
        return b",".join(parts)

    def fit_position(self,floor,x,y,map_type=0,context='',template_npc=False):
        if map_type or core.number(floor) in ({None,0} if template_npc else {None,0,777}) or core.number(x) is None or core.number(y) is None:return x,y
        n=int(floor);m=self.base_maps.get(n)
        if m is None:m=next((m for m in self.map_entities if m['new_id']==n),None)
        if m is None:return x,y
        xx,yy=int(x),int(y)
        if 0<=xx<m['width'] and 0<=yy<m['height']:return x,y
        newx=max(1,min(m['width']-2,xx));newy=max(1,min(m['height']-2,yy))
        if m['variant']=='LS2MAP':
            data=m.get('data') or Path(m['source']).read_bytes();w,h=m['width'],m['height'];n=w*h
            def walk(a,b):
                index=(h-1-b)*w+a
                ground=struct.unpack_from('>H',data,44+index*2)[0];obj=struct.unpack_from('>H',data,44+n*2+index*2)[0]
                def allowed(v):return v==0 or self.tile_info.get(v,self.tile_info.get(v+200000,[]))[3:4]==[b'1']
                return allowed(ground) and allowed(obj)
            if not walk(newx,newy):
                found=[]
                for radius in range(1,max(w,h)):
                    for dx in range(-radius,radius+1):
                        for dy in range(-radius,radius+1):
                            if max(abs(dx),abs(dy))!=radius:continue
                            a,b=newx+dx,newy+dy
                            if 0<=a<w and 0<=b<h and walk(a,b):found.append((abs(a-xx)+abs(b-yy),a,b))
                    if found:break
                if found:_,newx,newy=min(found)
        self.notes.append({'kind':'custom_out_of_bounds_position_adapter','floor':int(floor),'from':[xx,yy],'to':[newx,newy],'context':context})
        return str(newx).encode(),str(newy).encode()

    def encount_param(self, unit, raw, context):
        parts = raw.split(b"|")
        if len(parts) < 10:
            self.missing.append({"unit": unit, "kind": "encount_parameter_shape", "context": context})
            return raw
        parts[1] = self.coord_tuple(unit, parts[1], context)
        for pos in [2]:
            if parts[pos] and core.number(parts[pos]) is not None and int(parts[pos]) > 0:
                parts[pos] = self.resolve(unit, "itemset", parts[pos], context)
        for pos in range(4, 8):
            if parts[pos] and core.number(parts[pos]) is not None and int(parts[pos]) > 0:
                parts[pos] = self.resolve(unit, "msg", parts[pos], context)
        if parts[9] and core.number(parts[9]) is not None and int(parts[9]) > 0:
            parts[9] = self.resolve(unit, "encount", parts[9], context)
        # The remaining numeric pairs are native event/action types, not messages.
        # Preserve their enum values rather than assigning message IDs to them.
        return b"|".join(parts)

    def pet_species(self,unit,value,context):
        n=core.number(value)
        if n is None or n<=0:return value
        if self.local.get((unit,'enemybase',n)) or n in self.base['enemybase'] or self.pool.get(('enemybase',n)):
            return self.resolve(unit,'enemybase',value,context)
        prior=len(self.missing);enemy=int(self.resolve(unit,'enemy',value,context))
        c=self.transformed.get(('enemy',enemy)) or self.base['enemy'].get(enemy)
        if c:
            del self.missing[prior:]
            return c[3]
        return value

    def transform_script(self, s):
        unit = s["unit"]
        transformed = []
        for ln, raw in enumerate(s["data"].replace(b"\r\n", b"\n").replace(b"\r", b"\n").split(b"\n"), 1):
            context = f"{s['path']}:{ln}"
            if raw.lstrip().startswith((b"#", b"//")):
                transformed.append(raw)
                continue
            # Keep quoted dialogue untouched; numeric references are executable tokens.
            pieces = re.split(rb'("(?:[^"\\]|\\.)*")', raw)
            for i in range(0, len(pieces), 2):
                p = pieces[i]
                p = re.sub(rb"\b(EndEvent|NowEvent|GlobalFlag)\s*(\d+)",
                           lambda m: m[1] + b" " + str(self.flag(unit, m[1].decode().lower(), m[2])).encode(), p, flags=re.I)
                p = re.sub(rb"\b(Item(?:All|One|Count)?|Give(?:Leak\d*|Stack|Time)?Item|Kill(?:Leak\d*)?Item(?:All)?)\s*(?=\d|\()(\d+)?",
                           lambda m: m[1] + b" " + (self.resolve(unit, "itemset", m[2], context) if m[2] else b""), p, flags=re.I)
                # Weighted item/pet reward lists retain their probabilities.
                if re.match(rb"\s*(?:Give(?:Leak\d*|Stack|Time)?Item|KillItem)\b", p, re.I):
                    p = re.sub(rb"(?<=[(,])(\d+)(?=%)", lambda m: self.resolve(unit, "itemset", m[1], context), p)
                p = re.sub(rb"\b(?:Warp)\s*,?\s*(-?\d+)\s*,\s*(-?\d+)\s*,\s*(-?\d+)\s*,\s*(-?\d+)",
                           lambda m: b"Warp " + self.coord_tuple(unit,b','.join(m.groups()),context), p, flags=re.I)
                p = re.sub(rb"^\s*(Encount)\s+(.+)", lambda m: b"Encount " + self.encount_param(unit, m[2], context), p, flags=re.I)
                p = re.sub(rb"\b(EndWindow|Window|Message|SystemMessage|SysMsg|SendMsgToAll)\s+(\d+)\b",
                           lambda m: m[1] + b" " + self.resolve(unit, "msg", m[2], context), p, flags=re.I)
                p = re.sub(rb"\b(GiveRecipe|Recipe)\s+(\d+)",
                           lambda m: m[1] + b" " + self.resolve(unit, "itemrecipe", m[2], context), p, flags=re.I)
                p = re.sub(rb'\b(HaveTitle|AddTitle|GiveTitle|DelTitle|SetTitle|Title)\s*([=!<>]*\s*)(\d+)',
                           lambda m:m[1]+b' '+m[2]+self.resolve(unit,'titlename',m[3],context),p,flags=re.I)
                p = re.sub(rb"\b(Skill)\s+(\d+)", lambda m: m[1] + b" " + self.resolve(unit, "skill", m[2], context), p, flags=re.I)
                p = re.sub(rb"\b(Give(?:Leak\d*)?Pet)\s*(\d+)",
                           lambda m: m[1] + b" " + self.resolve(unit, "enemy", m[2], context), p, flags=re.I)
                p = re.sub(rb'\b(PetLevel|Pet|KillPet(?:L|H)?)\s*(\d+)',lambda m:m[1]+b' '+self.pet_species(unit,m[2],context),p,flags=re.I)
                if re.match(rb"\s*Give(?:Leak\d*)?Pet\b", p, re.I):
                    p = re.sub(rb"(?<=[(,])(\d+)(?=%)", lambda m: self.resolve(unit, "enemy", m[1], context), p)
                def job_reference(m):
                    command,operator,value=m.groups();op=operator.strip();number=int(value)
                    if command.lower()==b'job' and op in {b'<',b'>',b'<=',b'>='}:
                        # Numeric range endpoints (140..148, 430..450) are
                        # legal even when no job row has that exact number.
                        family=number//10*10
                        mapped=self.job_families.get((unit,family))
                        result=str(mapped+number%10).encode() if mapped is not None else value
                    else:result=self.resolve(unit,'jobs',value,context)
                    return command+b' '+operator+result
                p = re.sub(rb"\b(ChangeJob|JobChange|Job)\s*([=!<>]*\s*)(\d+)",job_reference,p,flags=re.I)
                p = re.sub(rb'\b(JobKind)\s+(\d+)',lambda m:m[1]+b' '+str(self.job_families.get((unit,int(m[2])),int(m[2]))).encode(),p,flags=re.I)
                p = self.filenames(unit, p, context)
                if hasattr(self,'legacy_item_conditions'):
                    def legacy_item_condition(m):
                        if m[1].decode() in self.legacy_item_conditions:
                            return b'Luac '+m[1]+b' '+m[2]+b' '+self.resolve(unit,'itemset',m[3],context)
                        return m[0]
                    p=re.sub(rb'\bLuac\s+(stp:legacy:[a-f0-9]+)\s*([=!<>]+)\s*(\d+)',legacy_item_condition,p,flags=re.I)
                pieces[i] = p
            transformed.append(b"".join(pieces))
        return b"\r\n".join(transformed)

    def field(self, c, col, unit, kind, context, positive=True):
        if col >= len(c) or not c[col] or core.number(c[col]) is None:
            return
        if positive and int(c[col]) <= 0:
            return
        c[col] = self.resolve(unit, kind, c[col], context, optional=positive)

    def transform_entity(self, entity):
        kind = entity["kind"]
        unit = entity["units"][0]
        c = entity["columns"].copy()
        context = f"{entity['path']}:{entity['line']}"
        c[SPECS[kind][0]] = str(entity["new_id"]).encode()
        f = lambda pos, target, positive=True: self.field(c, pos, unit, target, context, positive)
        if kind == "itemset":
            # Price is column 13; only gem material descriptors and messages are IDs.
            for pos in [84, 85, 86]:
                f(pos, "itemmaterial")
            f(94, "msg"); f(95, "msg")
            for i in range(len(c)):
                if b".txt" in c[i].lower():
                    c[i] = self.filenames(unit, c[i], context)
        elif kind == "enemy":
            old_base = core.number(c[3])
            # Source-supported spelling/number mistakes, and explicitly adapted
            # profiles for the two missing modified blades and the final Jeda.
            explicit = {('深海变异鱼',30830):30829,('幻歌妖',900350):900250,
                        ('异型蜂',410316):312,('土蜘蛛',410317):331,
                        ('改造血腥之刃',35):601,('改造杀龙之刃',36):602,
                        ('改造火焰之刃',37):603,('改造烈风之刃',38):604,
                        ('杰达',330135):330044}
            repair = explicit.get((label(c[0]).strip(),old_base))
            if repair is not None:
                c[3]=str(repair).encode()
                self.notes.append({'kind':'custom_missing_monster_profile_adapter','unit':unit,
                                   'name':label(c[0]),'from':old_base,'to':repair,'context':context})
                old_base=repair
            if label(c[0]).strip()=='耀阳花' and old_base==100276:
                matching=[r for r in self.entities['enemybase'] if label(r['columns'][0]).strip()=='耀阳花']
                if len(matching)==1:
                    c[3]=str(matching[0]['new_id']).encode()
                    # Already a globally unique rewritten ID; avoid a second lookup.
                    direct_base=True
                else: direct_base=False
            else: direct_base=False
            offset_base = old_base + 100000 if old_base is not None else -1
            own = self.local.get((unit, "enemybase", offset_base), [])
            if old_base not in self.base["enemybase"] and not self.pool.get(("enemybase", old_base)):
                if len(own) == 1 and 61100 <= old_base <= 61251:
                    c[3] = str(offset_base).encode()
                    self.notes.append({"kind": "source_monster_family_offset_repaired", "unit": unit, "from": old_base, "to": offset_base, "context": context})
                elif old_base is not None and old_base >= 400000 and old_base % 100000 in self.base["enemybase"]:
                    candidate = old_base % 100000
                    base_name = label(self.base["enemybase"][candidate][0]).strip()
                    if base_name and base_name in label(c[0]):
                        c[3] = str(candidate).encode()
                        self.notes.append({"kind": "legacy_monster_species_id_repaired", "unit": unit, "from": old_base, "to": candidate, "name": base_name, "context": context})
            old_ai = core.number(c[8])
            if old_ai is not None and 61100 <= old_ai <= 61251 and old_ai not in self.base["enemyai"] and not self.pool.get(("enemyai", old_ai)) and self.local.get((unit, "enemyai", old_ai+100000)):
                c[8] = str(old_ai+100000).encode()
                self.notes.append({"kind": "source_ai_family_offset_repaired", "unit": unit, "from": old_ai, "to": old_ai+100000, "context": context})
            if not direct_base: f(3, "enemybase", False)
            f(8, "enemyai", False); f(11, "enemytalk")
            for pos in list(range(13, 23)) + list(range(33, 38)):
                f(pos, "itemset")
            for pos in [45, 46]:
                f(pos, "enemy")
        elif kind == "enemybase":
            for pos in range(36, min(46, len(c))):
                f(pos, "tech")
        elif kind == "enemyai":
            for pos in range(21, min(31, len(c))):
                f(pos, "tech")
        elif kind == "group":
            f(3, "itemset"); f(4, "itemset")
            for pos in range(5, min(15, len(c))):
                f(pos, "enemy")
        elif kind == "encount":
            if len(c) > 3 and int(c[3] or b"0") != 777:
                c[3] = self.floor(unit, c[3], int(c[2] or b"0"), context)
            for pos in range(14, min(24, len(c))):
                f(pos, "group")
        elif kind == "dungeonconf":
            c[9] = self.floor(unit, c[9], int(c[8] or b"0"), context)
            c[15] = self.floor(unit, c[15], int(c[14] or b"0"), context)
            for pos in [10,12]:c[pos],c[pos+1]=self.fit_position(c[9],c[pos],c[pos+1],int(c[8] or b'0'),context)
            for pos in [16,18]:c[pos],c[pos+1]=self.fit_position(c[15],c[pos],c[pos+1],int(c[14] or b'0'),context)
            if not c[49] or core.number(c[49])==0:
                supplied=self.unit_by_id[unit]['tables'].get('encount',[])
                if supplied:
                    previous=label(c[49]);c[49]=supplied[0]['columns'][0]
                    self.notes.append(dict(kind='custom_dungeon_empty_encounter_adapter',unit=unit,path=entity['path'],line=entity['line'],before=previous,encount_source_id=int(c[49]),reason='Use the encounter provided alongside the incomplete dungeon instead of invalid zero'))
            f(49, "encount")
            for pos in range(57, 97, 4):
                f(pos, "itemset")
            f(97, "npc")
            for pos in range(101, min(117, len(c)), 2):
                f(pos, "npc")
        elif kind == "tech":
            f(4, "msg")
            if c[1].startswith((b"TECH_Mon", b"TECH_Enemy")) and not self.local.get((unit, "skill", int(c[5] or b"0"))) and int(c[5] or b"0") not in self.base["skill"]:
                pass  # Monster-only Tech can legally have an orphan skill grouping.
            else:
                f(5, "skill", False)
            if c[1] == b"TECH_MergeItem" and len(c) >= 15 and core.number(c[13]) is not None and core.number(c[14]) is not None:
                low, high = int(c[13]), int(c[14])
                recipes = [self.local[(unit, "itemrecipe", old)][0]["new_id"] for old in range(low, high+1) if self.local.get((unit, "itemrecipe", old))]
                if recipes:
                    c[13] = str(min(recipes)).encode(); c[14] = str(max(recipes)).encode()
                    self.notes.append({"kind": "craft_recipe_range_remapped", "unit": unit, "context": context, "recipes": sorted(recipes)})
        elif kind == "skill":
            f(2, "msg")
        elif kind == 'jobs':
            for pos in range(6,11):
                if c[pos]==b'881' and label(c[0]).strip().endswith(('斗士',)) and not self.pool.get(('skill',881)):
                    c[pos]=b'94'
                    self.notes.append({'kind':'custom_gladiator_prerequisite_adapted','unit':unit,'from':881,'to':94,'context':context,'reason':'The supplied class requires a skill that the pack does not define; use installed combat training'})
                f(pos,'skill')
        elif kind == "jobsancestry":
            for pos in range(2, 9): f(pos, "jobs", False)
        elif kind == "techarea":
            f(2, "skill", False)
            c[6] = self.floor(unit, c[6], int(c[5] or b"0"), context)
            for pos in range(13, min(23, len(c))):
                f(pos, "itemset")
        elif kind == "itemrecipe":
            f(2, "itemset", False); f(3, "skill", False)
            for pos in range(5, min(10, len(c))):
                f(pos, "itemset")
        elif kind == "enemytalk":
            for pos in range(11, min(16, len(c))):
                f(pos, "msg")
        elif kind == "ship":
            c[3] = self.floor(unit, c[3], int(c[2] or b"0"), context)
            for pos in range(6, min(15, len(c))):
                if c[pos] and core.number(c[pos]) and int(c[pos]) > 0:
                    c[pos] = self.floor(unit, c[pos], 0, context)
            for pos in [20, 23]:
                f(pos, "harbor")
        elif kind == "harbor":
            c[3] = self.floor(unit, c[3], int(c[2] or b"0"), context)
        elif kind == "npc":
            c = self.transform_npc(unit, {"columns": c, "path": entity["path"], "line": entity["line"]}, entity["new_id"])
        return c

    def transform_npc(self, unit, row, new_id=None):
        c = row["columns"][:25].copy()
        context = f"{row['path']}:{row['line']}"
        if len(c) != 25:
            return None
        if new_id is None:
            new_id = self.npc_cursor; self.npc_cursor += 1
        c[3] = str(new_id).encode()
        c[8] = self.floor(unit, c[8], int(c[7] or b"0"), context)
        for pos in range(9,17,2):c[pos],c[pos+1]=self.fit_position(c[8],c[pos],c[pos+1],int(c[7] or b'0'),context,template_npc=True)
        kind = c[0].strip().lower()
        c[24] = self.filenames(unit, c[24], context)
        p = c[24].split(b"|")
        if kind == b"standenemy":
            c[24] = self.encount_param(unit, c[24], context)
        elif kind == b"warp":
            if len(p) >= 4:
                p[1] = self.floor(unit, p[1], int(p[0] or b"0"), context)
                p[2],p[3]=self.fit_position(p[1],p[2],p[3],int(p[0] or b'0'),context)
                if len(p) > 5 and p[5]:
                    p[5] = self.resolve(unit, "msg", p[5], context,optional=True)
                if len(p)>6 and core.number(p[6]) is not None and int(p[6])>0:
                    p[6]=self.resolve(unit,'itemset',p[6],context)
                if len(p)>11 and core.number(p[9]) is not None and int(p[9])>0:
                    p[9]=self.floor(unit,p[9],int(p[0] or b'0'),context)
                    p[10],p[11]=self.fit_position(p[9],p[10],p[11],int(p[0] or b'0'),context)
                c[24] = b"|".join(p)
        elif kind in {b"townpeople", b"billboard", b"disemployment", b"timecard"}:
            c[24] = b"|".join(self.resolve(unit, "msg", x, context, optional=True) if x and core.number(x) is not None else x for x in p)
        elif kind == b"skillmaster":
            if p[0]:
                p[0] = self.resolve(unit, "skill", p[0], context)
            for i in range(1, len(p)):
                if p[i] and core.number(p[i]) and int(p[i]) > 0:
                    p[i] = self.resolve(unit, "msg", p[i], context)
            c[24] = b"|".join(p)
        elif kind in {b"spiritman", b"brushman", b"techshop", b"itemshop2", b"jobsmaster", b"vehicle"}:
            def parameter(pos, table):
                if pos < len(p) and p[pos] and core.number(p[pos]) is not None and int(p[pos]) > 0:
                    p[pos] = self.resolve(unit, table, p[pos], context)
            if kind == b"spiritman":
                for pos in range(1, len(p)): parameter(pos, "msg")
            elif kind == b"brushman":
                parameter(0, "itemset")
                for pos in range(1, min(6, len(p))): parameter(pos, "msg")
                for pos in range(6, len(p), 3): parameter(pos, "itemset")
            elif kind == b"techshop":
                for pos in range(1, min(6, len(p))): parameter(pos, "msg")
                for pos in range(6, len(p)): parameter(pos, "tech")
            elif kind == b"itemshop2":
                for pos in range(3, min(9, len(p))): parameter(pos, "msg")
                for pos in range(57, len(p)):parameter(pos,'itemset')
            elif kind == b"jobsmaster":
                if p and core.number(p[0]) is not None:
                    p[0]=str(self.job_families.get((unit,int(p[0])),int(p[0]))).encode()
                for pos in [4, 13]: parameter(pos, "itemset")
                for pos in list(range(6, 12)) + list(range(15, 38)) + [42, 43]: parameter(pos, "msg")
            elif kind == b"vehicle":
                for pos in range(10, len(p)): parameter(pos, "msg")
                if len(p) > 5 and p[5] and core.number(p[5]) is not None and self.map_local.get((unit, int(p[5]))):
                    p[5] = self.floor(unit, p[5], 0, context)
            c[24] = b"|".join(p)
            self.notes.append({"kind": "npc_parameter_review", "unit": unit, "npc_type": label(c[0]),
                               "context": context, "parameters": label(c[24])})
        elif kind == b"bus":
            source = next((x for x in self.unit_by_id[unit]["other_files"] if x["kind"] == "bus" and Path(x["path"]).name.casefold() == label(c[24]).casefold()), None)
            if source:
                props = {}
                for line in source["data"].splitlines():
                    if b":" in line:
                        key, value = line.split(b":", 1); props[key.strip().lower()] = value.strip()
                route = props.get(b"routeto1", b"").split(b";")[0].split(b",")
                if len(route) == 3 and all(core.number(x) is not None for x in route):
                    alias = "stp_bus_" + sha(source["path"].encode())[:16] + ".txt"
                    dest = self.floor(unit, route[0], 0, context)
                    level = int(props.get(b"levellimit", b"0") or b"0")
                    cost = int(props.get(b"needgold", b"0") or b"0")
                    message = props.get(b"msg_start") or "要搭乘这班车吗？".encode("gbk")
                    script = b'Block level < ' + str(level).encode() + b'\r\nEndWindow "' + (props.get(b"msg_level") or "等级不足。".encode("gbk")) + b'"\r\n'
                    script += b'Block\r\nWindow "' + message + b'",yes,no\r\nWindow_no\r\nEndWindow "' + "下次再来。".encode("gbk") + b'"\r\n'
                    script += b'Window_yes gold < ' + str(cost).encode() + b'\r\nEndWindow "' + (props.get(b"msg_gold") or "魔币不足。".encode("gbk")) + b'"\r\n'
                    script += b'Window_yes\r\nAddGold -' + str(cost).encode() + b'\r\nWarp 0,' + b",".join([dest, route[1], route[2]]) + b"\r\n"
                    self.files["gmsv/data/npc/" + alias] = script
                    c[0] = b"Event"; c[24] = alias.encode()
                    self.notes.append({"kind": "legacy_bus_native_event_adapter", "unit": unit, "path": source["path"], "alias": alias})
                else:
                    self.missing.append({"unit": unit, "kind": "bus_route_shape", "context": context})
            else:
                self.missing.append({"unit": unit, "kind": "missing_bus_file", "context": context, "name": label(c[24])})
        return c

    def stage(self):
        if (BATCH / "manifest.json").exists():
            manifest = json.loads((BATCH / "manifest.json").read_text(encoding="utf-8"))
            if manifest.get("status") == "applied":
                raise ValueError("installed batch cannot be rebuilt")
        STAGE.mkdir(parents=True, exist_ok=True)
        provenance = []
        for kind, entries in self.entities.items():
            for entity in entries:
                if entity["reuse_base"]:
                    continue
                c = self.transform_entity(entity)
                self.transformed[(kind,entity['new_id'])]=c
                self.additions[kind].append(c)
                provenance.append({k: v for k, v in entity.items() if k != "columns"})
        for u in self.units:
            for row in u["tables"].get("warp", []):
                c = row["columns"].copy()
                context = f"{row['path']}:{row['line']}"
                c[0] = str(self.warp_cursor).encode(); self.warp_cursor += 1
                c[1] = self.floor(u["id"], c[1], 0, context)
                c[4] = self.floor(u["id"], c[4], 0, context)
                c[2],c[3]=self.fit_position(c[1],c[2],c[3],0,context)
                c[5],c[6]=self.fit_position(c[4],c[5],c[6],0,context)
                self.additions["warp"].append(c)
            for row in u["tables"].get("titleconfig", []):
                raw = b"\t".join(row["columns"])
                raw = re.sub(rb"\bTITLE=(\d+)", lambda m: b"TITLE=" + self.resolve(u["id"], "titlename", m[1], row["path"]), raw, flags=re.I)
                raw = re.sub(rb"\bENDFLG=(\d+)", lambda m: b"ENDFLG=" + str(self.flag(u["id"], "endevent", m[1])).encode(), raw, flags=re.I)
                self.additions["titleconfig"].append([raw])
            for row in u["tables"].get("effect", []):
                self.additions["effect"].append(row["columns"])
            for s in u["scripts"]:
                self.files["gmsv/data/npc/" + s["alias"]] = self.transform_script(s)
            for row in u["tables"].get("skilllv", []):
                c = row["columns"].copy()
                if len(c) < 4 or core.number(c[1]) is None or core.number(c[2]) is None:
                    continue
                old_skill, old_job = c[1], c[2]
                if not self.local.get((u["id"], "skill", int(old_skill))) and int(old_skill) not in self.base["skill"] and not self.pool.get(('skill',int(old_skill))):
                    self.notes.append({"kind": "unused_limit_for_undefined_skill", "unit": u["id"], "id": int(old_skill), "path": row["path"]})
                    continue
                if not self.local.get((u["id"], "jobs", int(old_job))) and int(old_job) not in self.base["jobs"] and not self.pool.get(("jobs", int(old_job))):
                    self.notes.append({"kind": "unused_limit_for_undefined_job", "unit": u["id"], "id": int(old_job), "path": row["path"]})
                    continue
                c[1] = self.resolve(u["id"], "skill", c[1], row["path"])
                c[2] = self.resolve(u["id"], "jobs", c[2], row["path"])
                if tuple(c[1:3]) in self.base_cap_pairs:continue
                c[0] = str(self.allocate("skilllv")).encode()
                self.additions["skilllv"].append(c)
        for m in self.map_entities:
            data = bytearray(m["data"])
            if m["variant"] == "LS2MAP":
                struct.pack_into(">H", data, 6, m["new_id"])
            else:
                struct.pack_into(">I", data, 48, m["new_id"])
            self.files[f"gmsv/data/map/stp_{m['new_id']}"] = bytes(data)
        if self.additions.get('skilllv'):
            pairs={}
            for c in self.additions['skilllv']:
                key=(int(c[1]),int(c[2]))
                if key in pairs:
                    previous=pairs[key]
                    previous[3]=str(max(int(previous[3]),int(c[3]))).encode()
                    self.notes.append({'kind':'duplicate_imported_skill_limit_merged','skill':key[0],'job':key[1],'cap':int(previous[3])})
                else:pairs[key]=c
            self.additions['skilllv']=list(pairs.values())
        from build_shared_routes import build as build_routes
        build_routes(self)
        from build_shared_services import build as build_services
        build_services(self)
        from complete_shared_scripts import build as build_custom_scripts
        build_custom_scripts(self)
        from build_shared_task_guide import build as build_guide
        build_guide(self)
        manifest = {"status": "staged", "created_utc": datetime.now(timezone.utc).isoformat(), "files": {},
                    "source": str(SOURCE), "existing_rows_preserved": True, "production_runtime_restarted": False}
        for kind, cols in self.additions.items():
            original = self.stage_originals.get(kind + ".txt", b"")
            seen = set()
            unique = []
            for row in cols:
                raw = b"\t".join(row)
                if raw not in seen:
                    seen.add(raw); unique.append(raw)
            self.files["gmsv/data/" + kind + ".txt"] = original + (b"" if not original or original.endswith(b"\n") else b"\r\n") + b"\r\n".join(unique) + b"\r\n"
        setup=(ROOT/'gmsv/setup.cf').read_bytes()
        for name,value in [('othercharnum',100000),('npccreatenum',120000),('objnum',180000),('encountmemorynum',16000),('techareamemorynum',10000),('filesearchnum',25000)]:
            setup=re.sub(rb'(?m)^'+name.encode()+rb'=(\d+)',lambda m:name.encode()+b'='+str(max(int(m[1]),value)).encode(),setup)
        self.files['gmsv/setup.cf']=setup
        for relative, data in self.files.items():
            target = ROOT / relative
            before = target.read_bytes() if target.exists() else None
            staged = STAGE / relative
            staged.parent.mkdir(parents=True, exist_ok=True)
            staged.write_bytes(data)
            manifest["files"][relative] = {"before": sha(before) if before is not None else None, "after": sha(data), "bytes": len(data)}
        save(BATCH / "manifest.json", manifest)
        save(OUT / "id_mapping.json", {"entities": provenance, "maps": [{k: v for k, v in m.items() if k != "data"} for m in self.map_entities],
                                       "flags": [{"unit": u, "kind": kind, "old_id": old, "new_id": new} for (u, kind, old), new in self.flags.items()]})
        save(OUT / "source_units.json", [{"id": u["id"], "name": u["name"], "root": u["root"],
                                           "tables": {k: len(v) for k, v in u["tables"].items()},
                                           "scripts": len(u["scripts"]), "maps": len(u["maps"])} for u in self.units])
        save(OUT / "source_repairs.json", self.notes)
        save(OUT / "unresolved.json", self.missing)
        print(json.dumps({"units": len(self.units), "maps": len(self.map_entities), "scripts": sum(len(u["scripts"]) for u in self.units),
                          "added_rows": {k: len(v) for k, v in self.additions.items()}, "unresolved_by_kind": dict(collections.Counter(x["kind"] for x in self.missing)),
                          "notes_by_kind": dict(collections.Counter(x["kind"] for x in self.notes))}, ensure_ascii=False, indent=2))


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("mode", choices=["stage"])
    p.parse_args()
    b = Builder(); b.scan()
    from repair_shared_crafting import repair as repair_crafting
    repair_crafting(b)
    from scope_shared_task_tables import scope
    scope(b)
    from complete_shared_skills import complete as complete_skills
    complete_skills(b)
    from complete_shared_skillmasters import complete as complete_masters
    complete_masters(b)
    from complete_shared_jobs import complete as complete_jobs
    complete_jobs(b)
    from complete_shared_scripts import complete as complete_scripts
    complete_scripts(b)
    from translate_shared_legacy import complete as translate_legacy
    translate_legacy(b)
    from complete_shared_source_dependencies import complete
    complete(b)
    from complete_shared_assets import complete as complete_assets
    complete_assets(b)
    from complete_shared_missing_scenes import complete as complete_scenes
    complete_scenes(b)
    b.register(); b.stage()


if __name__ == "__main__":
    main()
