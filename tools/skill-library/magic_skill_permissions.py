"""Open installed skills to all seven magic-swordsman ranks, preserving other jobs."""
from pathlib import Path
import hashlib
import json
import shutil
from pet_skill_policy import pet_player_ids

ROOT = Path(__file__).resolve().parents[2]
MAGIC_JOBS = set(range(181, 188))


def install():
    path = ROOT / 'gmsv/data/skilllv.txt'
    original = path.read_bytes()
    blocked = pet_player_ids()
    skills = {int(r[1]) for line in (ROOT / 'gmsv/data/skill.txt').read_bytes().splitlines()
              if len(r := line.split(b'\t')) > 1 and r[1].isdigit()}
    output, seen, row_ids = [], set(), []
    changed = 0
    newline = b'\r\n' if b'\r\n' in original else b'\n'
    for line in original.splitlines(keepends=True):
        body = line.rstrip(b'\r\n')
        r = body.split(b'\t')
        if r[0].isdigit():
            row_ids.append(int(r[0]))
        if len(r) >= 4 and r[1].isdigit() and r[2].isdigit():
            sid, job = int(r[1]), int(r[2])
            if sid in skills and job in MAGIC_JOBS:
                seen.add((sid, job))
                cap = b'0' if sid in blocked else b'30'
                if r[3] != cap:
                    r[3] = cap
                    line = b'\t'.join(r) + line[len(body):]
                    changed += 1
        output.append(line)
    added = 0
    next_id = max(row_ids) + 1
    for sid in sorted(skills):
        for job in sorted(MAGIC_JOBS):
            if (sid, job) not in seen:
                if output and not output[-1].endswith(b'\n'):
                    output[-1] += newline
                cap = 0 if sid in blocked else 30
                output.append(f'{next_id}\t{sid}\t{job}\t{cap}'.encode('ascii') + newline)
                next_id += 1
                added += 1
    updated = b''.join(output)
    # Compare every unmodified job row byte-for-byte before installing.
    def other_jobs(raw):
        return [line for line in raw.splitlines(keepends=True)
                if len(r := line.rstrip(b'\r\n').split(b'\t')) < 4
                or not r[2].isdigit() or int(r[2]) not in MAGIC_JOBS]
    assert other_jobs(original) == other_jobs(updated), 'Other job rows changed'
    backup = ROOT / 'backups/magic_skills_20261010/before/gmsv/data/skilllv.txt'
    if updated != original:
        if not backup.exists():
            backup.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, backup)
        path.write_bytes(updated)
    report = {'skills': len(skills), 'excluded_pet_skills': len(blocked), 'jobs': sorted(MAGIC_JOBS), 'changed_rows': changed,
              'added_rows': added, 'other_jobs_unchanged': True,
              'sha256': hashlib.sha256(updated).hexdigest(), 'restart_required': True}
    out = ROOT / 'docs/skill_training/magic_skills_install.json'
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(report, indent=2) + '\n', 'utf-8')
    print(json.dumps(report))


if __name__ == '__main__':
    install()
