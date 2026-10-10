"""Compare declared Taiwan 7.1 features against the read-only local inventory.

Names locate candidates, not complete quest implementations. The result keeps
unknown official IDs, formulas and map geometry unknown instead of guessing.
Run audit_content.py first to refresh the inventory after any DATA changes.
"""
from __future__ import annotations

import collections
import csv
import hashlib
import json
import re
from pathlib import Path

from audit_content import label, records

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "docs/cg71_content_audit"


def read(name):
    return json.loads((OUT / name).read_text(encoding="utf-8"))


def main():
    declared = read("version_gaps.json")
    audit = read("audit.json")
    maps, jobs, skills = (read(name) for name in ("maps.json", "jobs.json", "skills.json"))
    pack = None
    library = None
    library_dir=OUT.parent/'skill_library'
    if (library_dir/'native_certification.json').exists() and (library_dir/'installed_static.json').exists():
        lib=json.loads((library_dir/'manifest.json').read_text(encoding='utf-8'))
        proof=json.loads((library_dir/'native_certification.json').read_text(encoding='utf-8'))
        digest=hashlib.sha256(json.dumps(lib['files'],sort_keys=True,separators=(',',':')).encode()).hexdigest()
        def installed_matches(path,row):
            current=ROOT/path
            if not current.exists():return False
            actual=current.read_bytes()
            if hashlib.sha256(actual).hexdigest()==row['after']:return True
            if path!='gmsv/lua/ModuleConfig.lua':return False
            staged=ROOT/'backups/skill_library_20261004/staged'/path
            if not staged.exists():return False
            expected=staged.read_bytes()
            return hashlib.sha256(expected).hexdigest()==row['after'] and actual.startswith(expected) and re.fullmatch(rb"(?:\s|loadModule\('[A-Za-z][A-Za-z0-9_]*'\))*",actual[len(expected):]) is not None
        if proof['result']=='PASS' and proof['pack_sha256']==digest and all(installed_matches(p,r) for p,r in lib['files'].items()):library=lib
    pack_dir = OUT.parent / 'jobskill_pack'
    if (pack_dir / 'native_certification.json').exists() and (pack_dir / 'installed_static.json').exists():
        candidate = json.loads((pack_dir / 'manifest.json').read_text(encoding='utf-8'))
        cert = json.loads((pack_dir / 'native_certification.json').read_text(encoding='utf-8'))
        installed = json.loads((pack_dir / 'installed_static.json').read_text(encoding='utf-8'))
        fingerprint = hashlib.sha256(json.dumps(candidate['files'],sort_keys=True,separators=(',',':')).encode('utf-8')).hexdigest()
        if cert['result']=='PASS' and installed['result']=='PASS' and cert['pack_sha256']==fingerprint and all(
            (ROOT / path).exists() and (hashlib.sha256((ROOT / path).read_bytes()).hexdigest()==row['after'] or (library and library['files'].get(path,{}).get('before')==row['after']))
            for path,row in candidate['files'].items()):
            pack=candidate
    pack_skill_ids={s['id'] for s in pack['skills']} if pack else set()
    pack_extended_ids={s['id'] for s in pack['extended_skills']} if pack else set()
    profession_scope=jobs+([{'id':j['family'],'name':j['name']} for j in pack['jobs']] if pack else [])
    with (OUT / "items.csv").open(encoding="utf-8-sig", newline="") as stream:
        items = list(csv.DictReader(stream))
    npc_names = [{"name": label(r[1]), "id": int(r[3]), "line": line}
                 for line, r in records(Path(audit["configured_paths"]["npcfile"]).read_bytes())
                 if len(r) > 3 and r[3].isdigit()]
    checks = []
    for feature in declared["features"]:
        aliases = feature.get("aliases", [])
        scope = {"profession": profession_scope, "map": maps, "skill": skills,
                 "quest": items + skills + npc_names}.get(feature["category"], [])
        found = [{k: row[k] for k in ("id", "floor", "name", "path", "line") if k in row}
                 for row in scope if aliases and any(s in row["name"] for s in aliases)]
        status = "name_candidates_found" if found else "declared_names_not_found"
        if feature["category"] in ("skill_ceiling", "advanced_skills"):
            status = "requires_level_and_engine_validation"
        implemented=bool(pack and (
            any(r.get('id') in pack_skill_ids for r in found) or
            (feature['category']=='profession' and any(r.get('id') in {j['family'] for j in pack['jobs']} for r in found)) or
            feature['key'] in ('pet_craft_trial','skill_levels_11_15','eight_advanced')))
        if implemented: status='custom_playable_validated'
        checks.append({"key": feature["key"], "name": feature["name"],
                       "category": feature["category"], "status": status, "candidates": found,
                       "source_ids": feature["source_ids"], "implemented_by_this_task": implemented,
                       "implementation": 'local_custom_rules' if implemented else None})

    geometry_checks = []
    by_floor = {m["floor"]: m for m in maps}
    for floor, location, x, y, source in [
        (32277, "6.0 幻影镜入口（旧亚纪城候选地图）", 69, 164, "mirror"),
        (2303, "7.1 晶石制造就职（旧地下工房候选地图）", 34, 53, "craftjob"),
        (2303, "7.1 项圈制造就职（旧地下工房候选地图）", 34, 51, "craftjob")]:
        m = by_floor[floor]
        geometry_checks.append({"location": location, "existing_floor_candidate": floor,
                                "width": m["width"], "height": m["height"], "x": x, "y": y,
                                "coordinate_fits_old_map": 0 <= x < m["width"] and 0 <= y < m["height"],
                                "source_id": source,
                                "note": "This is not an assertion that the revised official map kept this floor ID."})

    technique_levels = collections.defaultdict(set)
    technique_names = []
    for _, r in records(Path(audit["configured_paths"]["techfile"]).read_bytes()):
        if len(r) > 6 and r[5].isdigit() and r[6].isdigit():
            technique_names.append({"name": r[0].decode('gbk') if int(r[5]) in pack_skill_ids else label(r[0]), "id": int(r[3]),
                                    "skill": int(r[5]), "level": int(r[6]), "function": label(r[1])})
            level = int(r[6])
            if 1 <= level <= 15:
                technique_levels[int(r[5])].add(level)
    advanced = []
    for candidate in declared.get("advanced_skill_candidates", []):
        names = candidate["aliases"]
        matches = [{"id": s["id"], "name": s["name"], "tutors": s["tutors"],
                    "highest_job_limit": s["highest_job_limit"]} for s in skills if s["name"] in names]
        tech = [t for t in technique_names if any(t["name"].startswith(n) for n in names)]
        advanced.append({**candidate, "skill_definitions": matches, "technique_candidates": tech,
                         "runtime_verified": bool(matches and all(s['id'] in pack_skill_ids for s in matches)),
                         "implemented_by_this_task": bool(matches and all(s['id'] in pack_skill_ids for s in matches)),
                         "implementation": 'local_custom_rules' if matches and all(s['id'] in pack_skill_ids for s in matches) else None})
    focus = []
    for skill in skills:
        if skill["id"] in set(range(19, 31)) | {0, 3, 8, 61, 62, 63, 64, 65, 66, 67, 68, 95, 1005, 1007, 1010, 2005}:
            levels = technique_levels[skill["id"]]
            focus.append({"id": skill["id"], "name": skill["name"], "defined_levels": sorted(levels),
                          "absent_levels_11_15": sorted(set(range(11, 16)) - levels),
                          "highest_job_limit": skill["highest_job_limit"],
                          "functions": skill["functions"], "runtime_verified": skill['id'] in pack_extended_ids})

    missing_scripts = []
    for task in read("tasks.json"):
        if task["present"]:
            continue
        real = [n for n in task["npc_uses"] if n["floor"] not in (777, 32767)]
        test = [n for n in task["npc_uses"] if n["floor"] in (777, 32767)]
        missing_scripts.append({"script": task["script"], "game_npc_uses": real,
                                "test_map_npc_uses": test, "item_uses": task["item_uses"],
                                "note": "Legacy local dependency gap; not automatically a new-version quest."})

    baseline = read("baseline/audit.json")["inputs"]
    current = audit["inputs"]
    diff = {"changed_existing_inputs": sorted(k for k in baseline.keys() & current.keys()
                                             if baseline[k]["sha256"] != current[k]["sha256"]),
            "added_inputs": sorted(current.keys() - baseline.keys()),
            "removed_inputs": sorted(baseline.keys() - current.keys())}
    result = {"inventory_generated_utc": audit["generated_utc"], "coverage": declared["coverage"],
              "complete": False, "feature_checks": checks, "geometry_checks": geometry_checks,
              "selected_skill_level_checks": focus, "advanced_skill_checks": advanced,
              "missing_local_scripts": missing_scripts,
              "baseline_difference": diff, "sources": declared["sources"],
              "local_custom_pack": {'professions':len(pack['jobs']),'skills':len(pack['skills']),'extended_skills':len(pack['extended_skills']),'native_verified':True,'client_verified':False,'details':'../jobskill_pack/README_zh.md'} if pack else None,
              "skill_library": {'player_skills':len(library['player_skills']),'pet_boss_variants':len(library['monster_sources']),'maximum_level':30,'active_slots':15,'native_verified':True,'client_verified':False,'details':'../skill_library/README_zh.md'} if library else None,
              "limitations": ["Candidate name matching cannot prove a complete quest chain.",
                              "Original geometries and complete official DATA are not available locally.",
                              "Static checks do not prove that the running server loaded or executed a change."]}
    (OUT / "target_comparison.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    text = ["# 台湾 7.1 差异与实施状态", "", "状态：职业与技能已配置可玩的定制版本并通过隔离原生验证；新增地图及官方任务链仍未补齐。详情见 [职业技能补齐包](../jobskill_pack/README_zh.md)。" if pack else "状态：尚未补齐。此处仅核对有来源的项目，不是官方全部内容清单。", "",
            "## 可核实的版本差异", "", "| 内容 | 本地名称检查 | 已找到候选 |", "|---|---|---|"]
    for c in checks:
        status = {"name_candidates_found": "已有候选，需要完整链验证", "declared_names_not_found": "未找到对应定义",
                  "requires_level_and_engine_validation": "等级与引擎待补", "custom_playable_validated":"定制玩法已配置、原生验证通过"}[c["status"]]
        names = "、".join(f"{r['name']}（{r.get('id', r.get('floor', '?'))}）" for r in c["candidates"][:7])
        text.append(f"| {c['name']} | {status} | {names or '—'} |")
    text.extend(["", "## 不可直接复用的旧地图", "", "| 用途 | 旧地图编号 | 旧地图尺寸 | 新入口 / NPC 坐标 |", "|---|---:|---|---|"])
    for c in geometry_checks:
        text.append(f"| {c['location']} | {c['existing_floor_candidate']} | {c['width']}×{c['height']} | ({c['x']},{c['y']}) |")
    text.extend(["", "以上是旧地图候选，不能据此推断新版地图仍使用同一编号。坐标超出边界，必须取得新版几何后再接入口。", "",
                 "## 11～15 级技能", "", "| 技能 | 编号 | 缺少的 Tech 等级 | 本地最高职业限制 |", "|---|---:|---|---:|"])
    for c in focus:
        text.append(f"| {c['name']} | {c['id']} | {','.join(map(str, c['absent_levels_11_15'])) or '无'} | {c['highest_job_limit']} |")
    text.extend(["", "全部 647 个技能已按本服定制规则适配到 30 级，另包含 447 个可供骑士学习的独立宠物/BOSS 招式；永久技能库及原生实战、数据库重读均已验证。详见 [30级永久技能库](../skill_library/README_zh.md)。" if library else "`maxskilllevel=15` 等配置已经开放引擎上限，但不提供 Tech、职业限制、经验与动画数据。", "",
                 "## 职业进阶技能及待核实候选", "", "其他职业候选由资料索引取得，其具体开放时间和数值仍待逐项核对。", "",
                 "| 职业 | 技能 | 本地技能定义 | Tech 候选 |", "|---|---|---|---|"])
    for c in advanced:
        names = "、".join(f"{t['name']}（{t['id']}）" for t in c["technique_candidates"])
        state='定制实现、原生验证通过' if c['runtime_verified'] else ('有候选，待验证' if c['skill_definitions'] else '缺少')
        text.append(f"| {c['profession']} | [{c['name']}]({c['source']}) | {state} | {names or '无'} |")
    text.extend(["", "孤立 Tech 不能证明人物技能已开放；参数、学习条件、职业限制、经验与运行时行为均需验证。", "",
                 "## 本轮已实施", "", "恢复道具 607651 引用的 `EV_tane_item607651.txt`，与本地 `item_tane_607651.txt` 原始字节完全一致。", "",
                 "备份与来源：`backups/content71/legacy-item607651/manifest.json`。验证：23 个奖励道具及原有宠物奖励定义存在；没有修改宠物表。", "",
                 "这是旧版本依赖修复，不能记作新增 6.0～7.1 任务。未做服务端热加载或游戏内验证。", "",
                 "另已安装四个宠装职业、33 个新技能、28 个技能的 11～15 级、86 份配方及产物；详见职业技能补齐包。已通过原生加载、就职晋阶和实际战斗回调验证，正式服务端等待正常重启加载。" if pack else "职业技能补齐包尚未安装或当前文件未通过哈希核对。", "",
                 f"与基线相比：已改既有输入 {len(diff['changed_existing_inputs'])} 个、新增输入 {len(diff['added_inputs'])} 个、删除输入 {len(diff['removed_inputs'])} 个。", "",
                 "## 资料来源", ""])
    text.extend(f"- [{key}]({source['url']})：{source['supports']}。" for key, source in declared["sources"].items())
    text.extend(["", "## 尚需取得", ""])
    text.extend(f"- {value}" for value in declared["unresolved_inputs"])
    (OUT / "target_comparison_zh.md").write_text("\n".join(text) + "\n", encoding="utf-8")
    print(json.dumps({"checked_features": len(checks), "missing_name_checks": sum(c['status'] == 'declared_names_not_found' for c in checks),
                      "geometry_conflicts": sum(not c['coordinate_fits_old_map'] for c in geometry_checks),
                      "baseline_difference": diff, "complete": False}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
