"""Read-only crafting and job ancestry dependency inventory.

Recipe columns without a verified meaning remain opaque. Different recipe and
item names are review candidates, not sufficient grounds to overwrite an item.
"""
from __future__ import annotations

import collections
import json
from pathlib import Path

from audit_content import label, number, records, sha256

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "docs/cg71_content_audit"


def main():
    setup = {}
    for raw in (ROOT / "gmsv/setup.cf").read_bytes().splitlines():
        if raw.strip() and not raw.lstrip().startswith(b"#") and b"=" in raw:
            k, v = raw.split(b"=", 1)
            setup[label(k).strip()] = label(v).strip()
    inputs = {}

    def read(key, default):
        path = Path(setup.get(key, default))
        if not path.is_absolute():
            path = ROOT / "gmsv" / path
        data = path.read_bytes()
        inputs[path.relative_to(ROOT).as_posix()] = {"bytes": len(data), "sha256": sha256(data)}
        return list(records(data))

    items = {number(r[11]): {"name": label(r[1]), "line": line}
             for line, r in read("itemfile", "data/itemset.txt") if len(r) > 11}
    jobs = {number(r[2]): label(r[0]) for _, r in read("jobsfile", "data/jobs.txt") if len(r) > 2}
    skills = {number(r[1]): label(r[0]) for _, r in read("skillfile", "data/skill.txt") if len(r) > 1}
    recipes, findings = [], []
    ids = collections.Counter()
    for line, r in read("itemrecipefile", "data/itemrecipe.txt"):
        if len(r) < 15:
            findings.append({"kind": "short_recipe_record", "line": line, "columns": len(r)})
            continue
        recipe_id, output, skill_id = number(r[1]), number(r[2]), number(r[3])
        ids[recipe_id] += 1
        materials = []
        for col in range(5, 10):
            material = number(r[col])
            if material is None or material < 0:
                continue
            count = number(r[col + 5])
            materials.append({"id": material, "count": count, "name": items.get(material, {}).get("name")})
            if material not in items:
                findings.append({"kind": "recipe_material_without_item", "recipe": recipe_id,
                                 "line": line, "item": material})
            if count is None or count <= 0:
                findings.append({"kind": "invalid_material_count", "recipe": recipe_id, "line": line,
                                 "item": material, "count": count})
        if output not in items:
            findings.append({"kind": "recipe_output_without_item", "recipe": recipe_id, "line": line, "item": output})
        if skill_id not in skills:
            findings.append({"kind": "recipe_skill_without_definition", "recipe": recipe_id, "line": line, "skill": skill_id})
        output_name = items.get(output, {}).get("name")
        recipes.append({"id": recipe_id, "name": label(r[0]), "line": line, "output_item": output,
                        "output_item_name": output_name, "skill": skill_id,
                        "skill_name": skills.get(skill_id), "materials": materials,
                        "name_differs_from_item": output_name is not None and label(r[0]) != output_name,
                        "opaque_columns": {"4": label(r[4])}})
    findings.extend({"kind": "duplicate_recipe_id", "id": k, "count": v} for k, v in ids.items() if v > 1)
    recipe_ids = set(ids)
    craft_levels = []
    for line, r in read("techfile", "data/tech.txt"):
        if len(r) < 15 or r[1] != b"TECH_MergeItem":
            continue
        low, high = number(r[13]), number(r[14])
        empty = low is None or high is None
        absent = [] if empty or high < low else sorted(set(range(low, high + 1)) - recipe_ids)
        craft_levels.append({"technique": number(r[3]), "skill": number(r[5]), "name": label(r[0]),
                             "skill_name": skills.get(number(r[5])), "level": number(r[6]), "line": line,
                             "recipe_first": low, "recipe_last": high, "empty_recipe_range": empty,
                             "absent_recipe_ids": absent})
        if absent:
            findings.append({"kind": "sparse_recipe_range", "severity": "information",
                             "technique": number(r[3]), "line": line, "unused_ids_in_range": absent,
                             "note": "Recipe IDs need not be contiguous. These holes are not missing content by themselves."})
    ancestry = []
    for line, r in read("jobs_ancestryfile", "data/jobsancestry.txt"):
        if len(r) < 9:
            findings.append({"kind": "short_ancestry_record", "line": line, "columns": len(r)})
            continue
        family = number(r[1])
        ranks = [number(v) for v in r[2:9]]
        missing = [v for v in ranks if v is not None and v not in jobs]
        ancestry.append({"family": family, "label": label(r[0]), "line": line, "rank_job_ids": ranks,
                         "rank_names": [jobs.get(v) for v in ranks], "absent_jobs": missing,
                         "opaque_remaining_columns": [label(v) for v in r[9:]]})
        if missing:
            findings.append({"kind": "ancestry_without_job", "family": family, "line": line, "job_ids": missing})
    families = {a["family"] for a in ancestry}
    for job_id in jobs:
        if job_id is not None and job_id - job_id % 10 not in families:
            findings.append({"kind": "job_without_ancestry_family", "job": job_id})
    result = {"scope": "local crafting and ancestry references; not complete official 7.1 DATA",
              "inputs": inputs, "stats": {"recipes": len(recipes), "ancestry_families": len(ancestry),
                                           "craft_techniques": len(craft_levels),
                                           "empty_craft_recipe_ranges": sum(c["empty_recipe_range"] for c in craft_levels),
                                           "recipe_and_output_name_differences": sum(r["name_differs_from_item"] for r in recipes)},
              "recipes": recipes, "craft_levels": craft_levels, "ancestry": ancestry, "findings": findings,
              "limitations": ["Recipe and item names can legitimately differ; review before changing DATA.",
                              "An empty future-level crafting row does not implement any recipe.",
                              "Rank/equipment/skill balance is not inferred from existing classes."]}
    (OUT / "crafting.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"stats": result["stats"], "findings": dict(collections.Counter(f["kind"] for f in findings))},
                     ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
