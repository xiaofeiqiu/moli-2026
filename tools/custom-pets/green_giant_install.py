"""Add a modified ordinary giant without altering existing DATA rows or saves."""
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[2]
PET_ID = 800412
NAME = '改造绿巨人'
BACKUP = ROOT / 'backups/green_giant_20261011/data_before'


def main():
    records = []
    for filename, key in [('enemybase.txt', 1), ('enemy.txt', 2)]:
        path = ROOT / 'gmsv/data' / filename
        raw = path.read_bytes()
        rows = [line.split(b'\t') for line in raw.splitlines()]
        donor = [r for r in rows if len(r) > key and r[key] == b'811']
        assert len(donor) == 1, filename
        row = donor[0].copy()
        row[0] = NAME.encode('gbk')
        row[key] = str(PET_ID).encode()
        if filename == 'enemybase.txt':
            assert donor[0][5:10] == [b'36', b'33', b'22', b'7', b'12']
            row[6], row[8] = b'45', b'25'
        else:
            row[3] = str(PET_ID).encode()
        existing = [r for r in rows if len(r) > key and r[key] == str(PET_ID).encode()]
        assert not existing or existing == [row], f'{filename}: {PET_ID} already occupied'
        newline = b'\r\n' if b'\r\n' in raw else b'\n'
        after = raw if existing else raw + (b'' if raw.endswith(b'\n') else newline) + b'\t'.join(row) + newline
        records.append((path, raw, after))
    # Validate both ID namespaces before writing either file.
    BACKUP.mkdir(parents=True, exist_ok=True)
    for path, before, after in records:
        backup = BACKUP / path.name
        if not backup.exists():
            backup.write_bytes(before)
        if after != before:
            path.write_bytes(after)
        assert path.read_bytes() == after
    report = {
        'name': NAME, 'enemy_id': PET_ID, 'enemy_base_id': PET_ID,
        'donor_enemy_id': 811, 'donor_enemy_base_id': 811,
        'growth': {'vital': 36, 'strength': 45, 'toughness': 22, 'quickness': 25, 'magic': 12, 'total': 140},
        'growth_unit': 'species base ranks; native FullArtRank includes the engine +2 adjustment per attribute',
        'race': '人形系', 'elements': {'earth': 100, 'water': 0, 'fire': 0, 'wind': 0},
        'appearance_id': 101810, 'skill_slots': 6, 'initial_skills': [7300, 7400, 330],
        'all_other_donor_fields_preserved': True, 'production_database_modified': False,
        'restart_required': True, 'acquisition': '/getPet 800412 (GM)',
        'files': [{
            'path': p.relative_to(ROOT).as_posix(),
            'sha256': hashlib.sha256(after).hexdigest(),
            'backup': (BACKUP / p.name).relative_to(ROOT).as_posix()
        } for p, _, after in records]
    }
    output = ROOT / 'docs/custom_pets/green_giant.json'
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', 'utf-8')
    print(f'Installed {NAME}, Enemy/EnemyBase {PET_ID}, ranks 36/45/22/25/12. Restart required.')


if __name__ == '__main__':
    main()
