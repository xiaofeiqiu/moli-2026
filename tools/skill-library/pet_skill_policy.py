"""Deny player jobs access to pet-source skills using the shared Lua catalog."""
from pathlib import Path
import json
import re
import shutil

ROOT = Path(__file__).resolve().parents[2]


def pet_player_ids():
    catalog = (ROOT / 'gmsv/lua/Modules/skillTrainingData.lua').read_bytes().decode('gbk')
    players = re.search(r'\["players"\]=\{(.*?)\},\["pets"\]=', catalog, re.S)
    assert players, 'Player catalog missing'
    result = set()
    for record in re.findall(r'\{([^{}]*)\}', players[1]):
        if '["source"]="pet"' in record:
            result.add(int(re.search(r'\["id"\]=(\d+)', record)[1]))
    assert result, 'Pet-source skill catalog is empty'
    return result


def install():
    blocked = pet_player_ids()
    path = ROOT / 'gmsv/data/skilllv.txt'
    original = path.read_bytes()
    jobs = {int(f[2]) for line in (ROOT / 'gmsv/data/jobs.txt').read_bytes().splitlines()
            if len(f := line.split(b'\t')) > 2 and f[2].isdigit()}
    output, changed, pairs = [], 0, set()
    for line in original.splitlines(keepends=True):
        body = line.rstrip(b'\r\n'); fields = body.split(b'\t')
        if len(fields) >= 4 and fields[1].isdigit() and fields[2].isdigit():
            pairs.add((int(fields[1]), int(fields[2])))
        if len(fields) >= 4 and fields[1].isdigit() and int(fields[1]) in blocked and fields[3] != b'0':
            fields[3] = b'0';line = b'\t'.join(fields) + line[len(body):];changed += 1
        output.append(line)
    newline = b'\r\n' if b'\r\n' in original else b'\n'
    missing = sorted((sid, job) for sid in blocked for job in jobs if (sid, job) not in pairs)
    output.extend(f'pet-only\t{sid}\t{job}\t0'.encode('ascii') + newline for sid, job in missing)
    updated = b''.join(output)
    if updated != original:
        backup = ROOT / 'backups/pet_skill_separation_20261010/before/gmsv/data/skilllv.txt'
        if not backup.exists():
            backup.parent.mkdir(parents=True, exist_ok=True);shutil.copy2(path, backup)
        path.write_bytes(updated)
    report = {'blocked_player_skills': len(blocked), 'changed_permission_rows': changed, 'added_denials': len(missing), 'restart_required': True}
    print(json.dumps(report))
    return report


if __name__ == '__main__':
    install()
