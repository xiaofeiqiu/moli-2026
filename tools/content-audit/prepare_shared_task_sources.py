"""Read the task pack and materialize nested DATA, never run bundled programs."""
from __future__ import annotations

import hashlib
import json
import re
import sys
import zipfile
from pathlib import Path, PurePosixPath

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
SOURCE = Path(r"D:\BaiduNetdiskDownload\全部任务共享\全部任务共享")
BATCH = ROOT / "backups/content71/shared-task-integration-20261004"
OUT = ROOT / "docs/cg71_content_audit/shared_integration"
sys.path.insert(0, str(HERE / ".deps"))


def digest(b):
    return hashlib.sha256(b).hexdigest()


def safe_member(name, root):
    parts = PurePosixPath(name.replace("\\", "/")).parts
    if not parts or any(p in {".", ".."} or not p or re.search(r'[<>:"|?*\x00-\x1f]', p)
                        or p.endswith((".", " ")) for p in parts):
        raise ValueError(f"unsafe archive path: {name!r}")
    if PurePosixPath(name.replace("\\", "/")).is_absolute():
        raise ValueError("absolute archive path")
    target = root.joinpath(*parts).resolve()
    if not target.is_relative_to(root.resolve()):
        raise ValueError("archive path outside stage")
    return target


def main():
    import rarfile
    rarfile.UNRAR_TOOL = str(HERE / ".deps/unrar.exe")
    rarfile.tool_setup(force=True, unrar=True, unar=False, bsdtar=False, sevenzip=False, sevenzip2=False)
    OUT.mkdir(parents=True, exist_ok=True)
    (BATCH / "nested").mkdir(parents=True, exist_ok=True)
    result = {"source": str(SOURCE), "archives": [], "programs_executed": False}
    excluded = {".exe", ".dll", ".com", ".bat", ".cmd", ".ps1", ".msi", ".lnk", ".url"}
    archives = sorted(p for p in SOURCE.rglob("*") if p.suffix.lower() in {".rar", ".zip"})
    for n, path in enumerate(archives, 1):
        target_root = BATCH / "nested" / f"n{n:03d}"
        entry = {"source": str(path), "relative_source": path.relative_to(SOURCE).as_posix(),
                 "stage": str(target_root), "sha256": digest(path.read_bytes()), "members": []}
        is_rar = path.suffix.lower() == ".rar"
        try:
            with (rarfile.RarFile(path, charset="gbk") if is_rar else
                  zipfile.ZipFile(path, metadata_encoding="gbk")) as archive:
                for member in archive.infolist():
                    name = member.filename
                    is_dir = member.isdir() if is_rar else member.is_dir()
                    if is_dir:
                        continue
                    target = safe_member(name, target_root)
                    if is_rar and getattr(member, "file_redir", None):
                        raise ValueError(f"archive link is not permitted: {name}")
                    if not is_rar and (member.external_attr >> 16) & 0o170000 == 0o120000:
                        raise ValueError(f"archive link is not permitted: {name}")
                    record = {"name": name, "bytes": member.file_size, "excluded_program": target.suffix.lower() in excluded}
                    if not record["excluded_program"]:
                        data = archive.read(member)  # Both readers verify original CRC.
                        record["sha256"] = digest(data)
                        target.parent.mkdir(parents=True, exist_ok=True)
                        if target.exists():
                            if digest(target.read_bytes()) != record["sha256"]:
                                raise ValueError(f"staged file collision: {target}")
                        else:
                            target.write_bytes(data)
                    entry["members"].append(record)
        except Exception as exc:
            entry["error"] = f"{type(exc).__name__}: {exc}"
        result["archives"].append(entry)
    (OUT / "nested_sources.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"archives": len(archives), "errors": [(x["relative_source"], x["error"]) for x in result["archives"] if "error" in x],
                      "data_members": sum(not m["excluded_program"] for x in result["archives"] for m in x["members"]),
                      "excluded_programs": sum(m["excluded_program"] for x in result["archives"] for m in x["members"])}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
