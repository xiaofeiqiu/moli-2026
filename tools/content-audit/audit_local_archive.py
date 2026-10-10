"""Read the original server package without extracting or running its files.

The normal content audits use only the standard library. This optional inspector
uses py7zr from the task-local .deps directory to handle Unicode 7z member names.
Archive data is streamed into hash sinks; only reports are written to disk.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath


ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "docs" / "cg71_content_audit" / "sources"
sys.path.insert(0, str(Path(__file__).resolve().parent / ".deps"))


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def safe_member(name: str) -> PurePosixPath:
    member = PurePosixPath(name.replace("\\", "/"))
    if member.is_absolute() or ".." in member.parts or any(":" in p for p in member.parts):
        raise ValueError(f"Unsafe archive member: {name!r}")
    return member


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path)
    args = parser.parse_args()
    try:
        import py7zr
        from py7zr.io import HashIOFactory
    except ImportError as exc:
        raise SystemExit("This optional tool requires py7zr in tools/content-audit/.deps.") from exc

    archive = args.archive.resolve(strict=True)
    snapshot = archive.stat()
    tasks = json.loads((OUT.parent / "tasks.json").read_text(encoding="utf-8"))
    maps = json.loads((OUT.parent / "maps.json").read_text(encoding="utf-8"))
    current_map_paths = {m["path"] for m in maps}
    tables = {
        "gmsv/data/jobs.txt", "gmsv/data/jobsancestry.txt", "gmsv/data/skill.txt",
        "gmsv/data/tech.txt", "gmsv/data/skilllv.txt", "gmsv/data/itemrecipe.txt",
        "gmsv/data/itemset.txt", "gmsv/data/npc.txt", "gmsv/data/warp.txt",
    }
    factory = HashIOFactory()
    with py7zr.SevenZipFile(archive, "r") as package:
        if package.needs_password():
            raise SystemExit("Archive requires a password; no extraction attempted.")
        entries = package.list()
        metadata = []
        selected = []
        for entry in entries:
            member = safe_member(entry.filename)
            name = member.as_posix()
            metadata.append({
                "name": name, "bytes": entry.uncompressed, "crc32": entry.crc32,
                "is_file": entry.is_file, "is_directory": entry.is_directory,
                "is_symlink": entry.is_symlink,
            })
            if entry.is_file and (name.startswith("gmsv/data/map/") or name in tables):
                if entry.is_symlink:
                    raise ValueError(f"Selected member is a symlink: {name}")
                selected.append(entry.filename)
        if sum(m["bytes"] or 0 for m in metadata if m["name"] in selected) > 1024 ** 3:
            raise ValueError("Selected archive data exceeds the one-gigabyte audit limit.")
        print(f"Indexed {len(metadata)} entries; hashing {len(selected)} map/table files in memory.", flush=True)
        package.extract(targets=selected, factory=factory)

    checks = []
    for filename, sink in sorted(factory.products.items()):
        member = safe_member(filename)
        name = member.as_posix()
        local_path = ROOT.joinpath(*member.parts).resolve()
        if not local_path.is_relative_to(ROOT):
            raise ValueError(f"Local comparison outside workspace: {name}")
        local_exists = local_path.is_file()
        archive_hash = sink.hash.hexdigest()
        local_hash = sha256_file(local_path) if local_exists else None
        checks.append({
            "entry": name, "archive_bytes": sink.size(), "archive_sha256": archive_hash,
            "local_exists": local_exists,
            "local_bytes": local_path.stat().st_size if local_exists else None,
            "local_sha256": local_hash,
            "sha256_and_size_match": local_exists and archive_hash == local_hash
                and sink.size() == local_path.stat().st_size,
            "valid_current_map": name in current_map_paths,
        })
    archive_files = {m["name"] for m in metadata if m["is_file"]}
    missing_tasks = [t for t in tasks if not t["present"]]
    recoverable = []
    for task in missing_tasks:
        expected = "gmsv/data/npc/" + task["script"]
        matches = sorted(name for name in archive_files if name.casefold() == expected.casefold())
        if matches:
            recoverable.append({"script": task["script"], "archive_members": matches})
    map_checks = [c for c in checks if c["valid_current_map"]]
    table_checks = [c for c in checks if c["entry"] in tables]
    report = {
        "checked_utc": datetime.now(timezone.utc).isoformat(),
        "archive": str(archive), "archive_bytes": snapshot.st_size,
        "archive_sha256": sha256_file(archive), "reader": f"py7zr {py7zr.__version__}",
        "extracted_to_filesystem": False, "executed_archive_files": False,
        "index_complete": True, "entries": len(metadata),
        "valid_current_maps": len(current_map_paths), "maps_compared": len(map_checks),
        "maps_matching_sha256_and_size": sum(c["sha256_and_size_match"] for c in map_checks),
        "current_maps_absent_from_archive": sorted(current_map_paths - archive_files),
        "archive_map_files_outside_current_native_inventory": [
            c for c in checks if c["entry"].startswith("gmsv/data/map/") and not c["valid_current_map"]
        ],
        "tables_compared": len(table_checks),
        "tables_matching_sha256_and_size": sum(c["sha256_and_size_match"] for c in table_checks),
        "missing_script_count": len(missing_tasks), "recoverable_missing_scripts": recoverable,
        "checks": checks,
    }
    if archive.stat().st_size != snapshot.st_size or archive.stat().st_mtime_ns != snapshot.st_mtime_ns:
        raise RuntimeError("Archive changed during the audit; reports were not saved.")
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "cgmsv_archive_full_index.json").write_text(
        json.dumps({"archive": str(archive), "entries": metadata}, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    (OUT / "cgmsv_archive_validation.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8",
    )
    print(json.dumps({k: v for k, v in report.items() if k not in {
        "checks", "archive_map_files_outside_current_native_inventory",
    }}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
