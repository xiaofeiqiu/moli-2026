"""Restore ZIP-sourced Chinese names, with a verified plan and rollback journal.

This package was extracted using CP437 followed by Windows CP1252 best-fit.
Its original names are GBK, except two explicitly verified UTF-8 map names.
The original ZIP and file contents are never rewritten; only names are changed.
"""

from __future__ import annotations

import argparse
import ctypes
import hashlib
import json
import os
import stat
import zipfile
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath


WORKSPACE = Path(__file__).resolve().parents[2]
REPORTS = WORKSPACE / "docs" / "cg71_content_audit" / "sources"
ALLOWED_ROOT = Path(r"D:\BaiduNetdiskDownload\全部任务共享")
DEFAULT_MANIFEST = REPORTS / "shared_tasks_filename_repair.json"
UTF8_MAP_NAMES = {"7210_未知之地", "7211_未知神殿"}


def now() -> str:
    return datetime.now(timezone.utc).isoformat()


def digest(stream) -> str:
    hasher = hashlib.sha256()
    for block in iter(lambda: stream.read(1024 * 1024), b""):
        hasher.update(block)
    return hasher.hexdigest()


def file_digest(path: Path) -> str:
    with path.open("rb") as stream:
        return digest(stream)


def parts(name: str) -> tuple[str, ...]:
    value = PurePosixPath(name)
    if value.is_absolute() or not value.parts or ".." in value.parts:
        raise ValueError(f"Unsafe relative path: {name!r}")
    for part in value.parts:
        if any(c in part for c in '<>:"\\|?*') or any(ord(c) < 32 for c in part):
            raise ValueError(f"Invalid Windows filename: {name!r}")
        if part.endswith((" ", ".")):
            raise ValueError(f"Windows would normalize this filename: {name!r}")
        device = part.split(".")[0].upper()
        if device in {"CON", "PRN", "AUX", "NUL", *(f"COM{i}" for i in range(1, 10)), *(f"LPT{i}" for i in range(1, 10))}:
            raise ValueError(f"Reserved Windows filename: {name!r}")
    return value.parts


def guarded(root: Path, relative: str) -> Path:
    path = root.joinpath(*parts(relative))
    resolved = path.resolve()
    if resolved == root or not resolved.is_relative_to(root):
        raise ValueError(f"Path outside the explicitly named directory: {path}")
    current = path
    while current != root:
        if current.exists() and (current.is_symlink() or current.is_junction()):
            raise ValueError(f"Reparse point in repair path: {current}")
        current = current.parent
    return path


def root_path(value: str | Path) -> Path:
    root = Path(value).resolve(strict=True)
    if root != ALLOWED_ROOT.resolve(strict=True) or not root.is_dir() or root.is_symlink() or root.is_junction():
        raise ValueError("This repair is restricted to the user-named shared-task directory.")
    return root


def legacy_windows_name(text: str) -> str:
    convert = ctypes.WinDLL("kernel32", use_last_error=True).WideCharToMultiByte
    convert.argtypes = [ctypes.c_uint, ctypes.c_ulong, ctypes.c_wchar_p, ctypes.c_int,
                        ctypes.c_void_p, ctypes.c_int, ctypes.c_char_p, ctypes.POINTER(ctypes.c_int)]
    convert.restype = ctypes.c_int
    count = convert(1252, 0, text, len(text), None, 0, None, None)
    if not count:
        raise ctypes.WinError(ctypes.get_last_error())
    buffer = ctypes.create_string_buffer(count)
    if convert(1252, 0, text, len(text), buffer, count, None, None) != count:
        raise ctypes.WinError(ctypes.get_last_error())
    return buffer.raw.decode("cp1252")


def original_name(entry: zipfile.ZipInfo) -> str:
    if entry.flag_bits & 0x800:
        return entry.filename
    decoded = []
    for part in entry.filename.split("/"):
        raw = part.encode("cp437")
        try:
            name = raw.decode("gbk")
        except UnicodeError:
            name = raw.decode("utf-8")
            if name not in UTF8_MAP_NAMES:
                raise ValueError(f"Unverified mixed-encoding component: {part!r}")
        decoded.append(name)
    return "/".join(decoded).rstrip("/")


def save_manifest(path: Path, data: dict) -> None:
    if not path.resolve().is_relative_to(REPORTS.resolve()):
        raise ValueError("Repair records must remain inside the workspace report directory.")
    temporary = path.with_suffix(path.suffix + ".writing")
    temporary.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    temporary.replace(path)


def prepare(archive: Path, manifest: Path) -> None:
    if manifest.exists():
        raise ValueError("A repair manifest already exists; inspect or verify it before preparing again.")
    root = root_path(ALLOWED_ROOT)
    archive = archive.resolve(strict=True)
    if archive != root.with_suffix(".zip"):
        raise ValueError("Expected the original ZIP beside the shared-task directory.")
    entries = []
    seen_old, seen_new = set(), set()
    operations = []
    with zipfile.ZipFile(archive) as package:
        infos = package.infolist()
        if sum(i.file_size for i in infos) > 2 * 1024 ** 3 or len(infos) > 50000:
            raise ValueError("Archive exceeds this repair's size or entry-count limit.")
        for index, info in enumerate(infos):
            if info.flag_bits & 1 or stat.S_ISLNK(info.external_attr >> 16):
                raise ValueError("Encrypted or symlink archive entries are not supported.")
            old = legacy_windows_name(info.filename).rstrip("/")
            new = original_name(info)
            # The extractor appended (1) after the lossy blue/yellow-crystal
            # collision. The content hash below must still match the ZIP.
            if new == "全部任务共享/待修复/佣兵系列/npc/黄水晶.txt":
                legacy_path = PurePosixPath(old)
                old = str(legacy_path.with_name(legacy_path.stem + "(1)" + legacy_path.suffix))
            old_path = guarded(root, old)
            guarded(root, new)
            for value, seen in [(old, seen_old), (new, seen_new)]:
                key = value.casefold()
                if key in seen:
                    raise ValueError(f"Ambiguous or duplicate target path: {value}")
                seen.add(key)
            is_dir = info.is_dir()
            if (is_dir and not old_path.is_dir()) or (not is_dir and not old_path.is_file()):
                raise ValueError(f"Missing or mismatched extracted entry: {old_path}")
            record = {"old": old, "new": new, "directory": is_dir, "bytes": info.file_size}
            if not is_dir:
                if old_path.stat().st_size != info.file_size:
                    raise ValueError(f"File size differs from ZIP: {old_path}")
                local_hash = file_digest(old_path)
                with package.open(info) as stream:
                    archive_hash = digest(stream)  # ZipFile also checks the member's CRC.
                if local_hash != archive_hash:
                    raise ValueError(f"Extracted content differs from original ZIP: {old_path}")
                record.update(sha256=local_hash, archive_crc32=info.CRC)
            entries.append(record)
            if PurePosixPath(old).name != PurePosixPath(new).name:
                immediate_target = str(PurePosixPath(old).with_name(PurePosixPath(new).name))
                target_path = guarded(root, immediate_target)
                if target_path.exists():
                    raise ValueError(f"Immediate rename target already exists: {target_path}")
                operations.append({"source": old, "target": immediate_target, "directory": is_dir})
            if index and index % 2500 == 0:
                print(f"Checked {index}/{len(infos)} archive entries and file hashes.", flush=True)
    actual = {str(p.relative_to(root)).replace("\\", "/").casefold() for p in root.rglob("*")}
    if actual != seen_old:
        raise ValueError("Extracted directory contains unindexed or missing entries; no names changed.")
    operations.sort(key=lambda op: (-len(PurePosixPath(op["source"]).parts), op["source"]))
    result = {
        "prepared_utc": now(), "root": str(root), "archive": str(archive),
        "archive_bytes": archive.stat().st_size, "archive_sha256": file_digest(archive),
        "status": "planned", "entries": entries, "operations": operations, "journal": [],
        "summary": {"files_verified_against_zip_sha256": sum(not e["directory"] for e in entries),
                    "directories": sum(e["directory"] for e in entries), "renames": len(operations),
                    "file_renames": sum(not op["directory"] for op in operations),
                    "directory_renames": sum(op["directory"] for op in operations)},
    }
    save_manifest(manifest, result)
    print(json.dumps(result["summary"], ensure_ascii=False, indent=2))


def verify(data: dict, variant: str) -> None:
    root = root_path(data["root"])
    expected = set()
    for entry in data["entries"]:
        relative = entry[variant]
        expected.add(relative.casefold())
        path = guarded(root, relative)
        if entry["directory"]:
            if not path.is_dir():
                raise ValueError(f"Missing directory: {path}")
        elif not path.is_file() or path.stat().st_size != entry["bytes"] or file_digest(path) != entry["sha256"]:
            raise ValueError(f"Missing or changed file: {path}")
    actual = {str(p.relative_to(root)).replace("\\", "/").casefold() for p in root.rglob("*")}
    if actual != expected:
        raise ValueError("Repair directory has missing or additional entries.")


def rename_one(root: Path, source_name: str, target_name: str) -> None:
    source, target = guarded(root, source_name), guarded(root, target_name)
    if source.parent != target.parent or target.exists() or not source.exists():
        raise ValueError(f"Unsafe or conflicting same-directory rename: {source} -> {target}")
    source.rename(target)


def run(mode: str, manifest: Path) -> None:
    data = json.loads(manifest.read_text(encoding="utf-8"))
    root = root_path(data["root"])
    if mode == "verify":
        variant = "new" if data["status"] == "applied" else "old"
        verify(data, variant)
        print(json.dumps({"status": data["status"], "verified_files": data["summary"]["files_verified_against_zip_sha256"],
                          "file_contents_unchanged": True}, ensure_ascii=False))
        return
    archive = Path(data["archive"]).resolve(strict=True)
    if archive != root.with_suffix(".zip") or file_digest(archive) != data["archive_sha256"]:
        raise ValueError("The original ZIP backup changed or is missing.")
    if mode == "rollback":
        if data["status"] != "applied":
            raise ValueError("Only a fully applied, verified repair can be rolled back.")
        verify(data, "new")
        for operation in reversed(data["journal"]):
            rename_one(root, operation["target"], operation["source"])
        verify(data, "old")
        data.update(status="rolled_back", rolled_back_utc=now())
        save_manifest(manifest, data)
        print("Rolled back all names; file contents verified unchanged.")
        return
    if data["status"] == "applied":
        verify(data, "new")
        print("Repair already applied; names and hashes verified.")
        return
    if data["status"] != "planned" or data["journal"]:
        raise ValueError("This manifest requires manual inspection before applying.")
    verify(data, "old")
    data.update(status="applying", started_utc=now())
    save_manifest(manifest, data)
    journal_path = manifest.with_suffix(".journal.jsonl")
    try:
        with journal_path.open("x", encoding="utf-8") as journal:
            for index, operation in enumerate(data["operations"]):
                rename_one(root, operation["source"], operation["target"])
                data["journal"].append(operation)
                journal.write(json.dumps(operation, ensure_ascii=False) + "\n")
                journal.flush()
                os.fsync(journal.fileno())
                if index and index % 1000 == 0:
                    print(f"Renamed {index}/{len(data['operations'])} entries.", flush=True)
        verify(data, "new")
    except Exception:
        for operation in reversed(data["journal"]):
            rename_one(root, operation["target"], operation["source"])
        verify(data, "old")
        data.update(status="failed_reverted", reverted_utc=now())
        save_manifest(manifest, data)
        raise
    data.update(status="applied", completed_utc=now(), post_rename_hashes_verified=True)
    save_manifest(manifest, data)
    print(json.dumps({"status": "applied", **data["summary"], "contents_unchanged": True}, ensure_ascii=False, indent=2))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=["plan", "apply", "verify", "rollback"])
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    args = parser.parse_args()
    if args.mode == "plan":
        prepare(ALLOWED_ROOT.with_suffix(".zip"), args.manifest)
    else:
        run(args.mode, args.manifest)


if __name__ == "__main__":
    main()
