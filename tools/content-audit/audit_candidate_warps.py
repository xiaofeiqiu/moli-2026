"""Check staged warp records against actual configured maps; never write game DATA."""
from __future__ import annotations

import argparse
import collections
import json
from pathlib import Path

from audit_content import dump_json, native_map, records, sha256


def audit(root: Path, candidate: Path, out: Path):
    root = root.resolve()
    server = root / "gmsv"
    config = {}
    for raw in (server / "setup.cf").read_bytes().splitlines():
        if raw.strip() and not raw.lstrip().startswith(b"#") and b"=" in raw:
            key, value = raw.split(b"=", 1)
            config[key.strip().decode("ascii")] = value.strip().decode("ascii")

    def configured(key, default):
        value = Path(config.get(key, default))
        return value if value.is_absolute() else server / value

    maps = collections.defaultdict(list)
    invalid_maps = []
    for path in sorted(configured("mapdir", "data/map").iterdir()):
        if not path.is_file():
            continue
        with path.open("rb") as stream:
            magic = stream.read(6)
        if magic != b"LS2MAP":
            continue
        try:
            parsed = native_map(path.read_bytes())
        except ValueError as error:
            invalid_maps.append({"path": str(path), "error": str(error)})
            continue
        maps[parsed["floor"]].append(parsed)

    warp_bytes = configured("warpfile", "data/warp.txt").read_bytes()
    existing_ids, existing_positions = set(), set()
    for _, fields in records(warp_bytes):
        if len(fields) >= 7:
            try:
                row = [int(value) for value in fields[:7]]
            except ValueError:
                continue
            existing_ids.add(row[0])
            existing_positions.add(tuple(row[1:4]))

    candidate_bytes = candidate.read_bytes()
    source = json.loads(candidate_bytes)
    rows = source["rows"]
    if not isinstance(rows, list) or any(
        not isinstance(row, list) or len(row) != 7
        or any(type(value) is not int or value < 0 for value in row)
        for row in rows
    ):
        raise ValueError("candidate rows must contain seven nonnegative integers")
    id_counts = collections.Counter(row[0] for row in rows)
    position_counts = collections.Counter(tuple(row[1:4]) for row in rows)
    issues = []
    floors = sorted({row[column] for row in rows for column in (1, 4)})
    for index, row in enumerate(rows, 1):
        reasons = []
        if id_counts[row[0]] > 1:
            reasons.append("duplicate_candidate_warp_id")
        if row[0] in existing_ids:
            reasons.append("warp_id_already_in_configured_data")
        position = tuple(row[1:4])
        if position_counts[position] > 1:
            reasons.append("duplicate_candidate_source_position")
        if position in existing_positions:
            reasons.append("source_position_already_has_warp")
        for side, floor, x, y in (
            ("source", *row[1:4]), ("destination", *row[4:7])
        ):
            definitions = maps.get(floor, [])
            if not definitions:
                reasons.append(f"{side}_map_missing")
            elif len(definitions) != 1:
                reasons.append(f"{side}_map_id_ambiguous")
            elif not (x < definitions[0]["width"] and y < definitions[0]["height"]):
                reasons.append(f"{side}_coordinate_out_of_bounds")
        if reasons:
            issues.append({"candidate_row": index, "record": row, "reasons": reasons})

    result = {
        "source_url": source["source_url"],
        "status": "blocked" if issues or invalid_maps else "static_checks_only",
        "imported": False,
        "candidate_sha256": sha256(candidate_bytes),
        "configured_warp_sha256": sha256(warp_bytes),
        "candidate_count": len(rows),
        "unique_warp_ids": len(id_counts),
        "duplicate_warp_ids": sorted(key for key, count in id_counts.items() if count > 1),
        "existing_warp_id_conflicts": sorted(set(id_counts) & existing_ids),
        "required_floor_ids": floors,
        "missing_floor_ids": [floor for floor in floors if floor not in maps],
        "invalid_local_maps": invalid_maps,
        "blocked_row_count": len(issues),
        "row_issues": issues,
        "limitations": [
            "来源只包含部分出口，不能据此证明区域完整。",
            "尺寸检查不能证明碰撞、地形、图档或出口可通行。",
            "尚未取得候选地图，未导入或做运行时验证。",
        ],
    }
    out.mkdir(parents=True, exist_ok=True)
    dump_json(out / "angel_warp_validation.json", result)
    missing = ", ".join(map(str, result["missing_floor_ids"])) or "无"
    (out / "angel_warp_validation_zh.md").write_text(
        "# 天使大陆传送候选检查\n\n"
        f"来源：[作者公开坐标]({source['source_url']})。候选数据只保存在报告目录，未写入游戏 DATA。\n\n"
        f"共 {len(rows)} 条记录，{len(id_counts)} 个不同传送编号；"
        f"重复编号：{result['duplicate_warp_ids']}。"
        f"本地编号冲突：{result['existing_warp_id_conflicts']}。\n\n"
        f"涉及 {len(floors)} 个地图编号，本地缺少：{missing}。"
        f"{len(issues)} 条记录未通过导入前检查。\n\n"
        "地图附件尚未取得，碰撞、出口落点和区域完整性未验证。"
        "作者说明这些坐标只涵盖部分出入口；不能把候选记录当成已经实现的任务或完整地图包。\n",
        encoding="utf-8",
    )
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    args = parser.parse_args()
    result = audit(args.root, args.root / "docs/cg71_content_audit/sources/angel_warp_candidate.json",
                   args.root / "docs/cg71_content_audit")
    print(json.dumps({key: result[key] for key in (
        "status", "imported", "candidate_count", "duplicate_warp_ids",
        "existing_warp_id_conflicts", "missing_floor_ids", "blocked_row_count"
    )}, ensure_ascii=False))
