"""Restore one locally recoverable item-script reference, without editing DATA tables.

The item 607651 entry names EV_tane_item607651.txt, while the original script
is present as item_tane_607651.txt and explicitly consumes that same item.
This repairs a legacy dependency; it does not add any 6.0--7.1 content.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCE = "gmsv/data/npc/item_tane_607651.txt"
TARGET = "gmsv/data/npc/EV_tane_item607651.txt"
SOURCE_HASH = "dd9b663c7d8511f2c638f8cf54683cac35aba6dfbac93106e8dea92138d75690"
MANIFEST = "backups/content71/legacy-item607651/manifest.json"


def digest(data):
    return hashlib.sha256(data).hexdigest()


def local(relative):
    path = ROOT / relative
    path.resolve().relative_to(ROOT.resolve())
    return path


def rows(relative):
    for raw in local(relative).read_bytes().splitlines():
        if raw.strip() and not raw.lstrip().startswith((b"#", b"//")):
            yield raw.split(b"\t")


def dependencies():
    data = local(SOURCE).read_bytes()
    if digest(data) != SOURCE_HASH:
        raise ValueError("Original script changed; reassess before restoring it")
    items = {int(r[11]) for r in rows("gmsv/data/itemset.txt") if len(r) > 11}
    uses = [r for r in rows("gmsv/data/itemset.txt") if len(r) > 11 and r[11] == b"607651"]
    if len(uses) != 1 or b"EV_tane_item607651.txt" not in uses[0]:
        raise ValueError("Item 607651 no longer references the expected script")
    if not re.search(rb"KillItem\s+607651\s*,\s*1", data):
        raise ValueError("Source does not consume the referenced item")
    rewards = {int(v) for v in re.findall(rb"(\d+)%1\$1", data)}
    if not rewards or rewards - items:
        raise ValueError(f"Missing reward items: {sorted(rewards - items)}")
    pets = {int(v) for v in re.findall(rb"givepet\s+(\d+)", data, re.I)}
    enemy_rows = {int(r[2]): r for r in rows("gmsv/data/enemy.txt") if len(r) > 2}
    bases = {int(r[1]) for r in rows("gmsv/data/enemybase.txt") if len(r) > 1}
    if any(p not in enemy_rows or int(enemy_rows[p][3]) not in bases for p in pets):
        raise ValueError("Missing pet reward definition; leave pet tables to their owner")
    return data, sorted(rewards), sorted(pets)


def verify():
    data, rewards, pets = dependencies()
    if local(TARGET).read_bytes() != data:
        raise ValueError("Restored script differs from the original")
    return {"target": TARGET, "sha256": digest(data), "bytes": len(data),
            "item_reward_ids": rewards, "existing_pet_reward_ids": pets,
            "static_verified": True, "runtime_verified": False}


def apply():
    data, rewards, pets = dependencies()
    manifest = local(MANIFEST)
    target = local(TARGET)
    if target.exists():
        if not manifest.exists():
            raise ValueError("Target already exists without this patch's manifest; do not overwrite it")
        return verify()
    if manifest.exists():
        raise ValueError("Manifest exists but target is absent; inspect prior rollback first")
    manifest.parent.mkdir(parents=True, exist_ok=True)
    # Preserve source bytes for review and recovery; do not rewrite its encoding.
    snapshot = manifest.parent / "item_tane_607651.original.bin"
    with snapshot.open("xb") as stream:
        stream.write(data)
    record = {"created_at": datetime.now(timezone.utc).isoformat(), "root": str(ROOT),
              "action": "create_exact_script_alias", "source": SOURCE, "target": TARGET,
              "target_existed_before": False, "sha256": digest(data), "bytes": len(data),
              "item_reward_ids": rewards, "existing_pet_reward_ids": pets,
              "reason": "item 607651 references the absent alias; source consumes that exact item",
              "runtime_verified": False, "tables_modified": []}
    # Write provenance before creating the target, so interruption remains inspectable.
    with manifest.open("x", encoding="utf-8") as stream:
        json.dump(record, stream, ensure_ascii=False, indent=2)
        stream.write("\n")
    with target.open("xb") as stream:
        stream.write(data)
    return verify()


def rollback():
    manifest = local(MANIFEST)
    record = json.loads(manifest.read_text(encoding="utf-8"))
    if record.get("action") != "create_exact_script_alias" or record.get("target") != TARGET:
        raise ValueError("Unexpected manifest; refuse rollback")
    if record.get("target_existed_before") is not False:
        raise ValueError("Target was not created by this patch")
    if record.get("sha256") != SOURCE_HASH:
        raise ValueError("Manifest no longer describes the verified original script")
    target = local(TARGET)
    if target.exists():
        if digest(target.read_bytes()) != record["sha256"]:
            raise ValueError("Target has later edits; preserve them and refuse rollback")
        target.unlink()
    record["rolled_back_at"] = datetime.now(timezone.utc).isoformat()
    manifest.write_text(json.dumps(record, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return {"removed": TARGET, "manifest_preserved": str(manifest)}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("apply", "verify", "rollback"))
    args = parser.parse_args()
    print(json.dumps({"apply": apply, "verify": verify, "rollback": rollback}[args.action](),
                     ensure_ascii=False, indent=2))
