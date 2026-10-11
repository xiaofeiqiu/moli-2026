"""Add pet-only ordinary SpiracleShot ranks without changing existing techniques."""
from pathlib import Path
import json
import sys

ROOT = Path(__file__).resolve().parents[2]
FIRST_ID = 910400


def install_techs():
    path = ROOT / 'gmsv/data/tech.txt'
    raw = path.read_bytes()
    newline = b'\r\n' if b'\r\n' in raw else b'\n'
    records = {}
    for line in raw.decode('gbk').splitlines():
        row = line.split('\t')
        if len(row) > 12 and row[3].isdigit():
            records[int(row[3])] = row
    added = []
    for rank in range(1, 11):
        source = records[399 + rank]
        assert source[1] == 'TECH_SpiracleShot' and source[5] == '4'
        row = source.copy()
        row[0] = f'宠物气功弹LV{rank}'
        row[3] = str(FIRST_ID + rank - 1)
        row[6], row[12] = '30', '0'
        existing = records.get(int(row[3]))
        assert existing is None or existing == row, f'Tech ID collision: {row[3]}'
        if existing is None:
            added.append('\t'.join(row).encode('gbk') + newline)
    if added:
        backup = ROOT / 'backups/pet_qigong_20261010/before/gmsv/data/tech.txt'
        if not backup.exists():
            backup.parent.mkdir(parents=True, exist_ok=True)
            backup.write_bytes(raw)
        path.write_bytes(raw + (b'' if raw.endswith(b'\n') else newline) + b''.join(added))
    return len(added)


def main():
    added = install_techs()
    # Update only the pet catalog; the full builder also discovers these rows.
    from build import lua
    path = ROOT / 'docs/skill_training/catalog.json'
    data = json.loads(path.read_text('utf-8'))
    ids = set(range(FIRST_ID, FIRST_ID + 10))
    pets = [s for s in data['pets'] if s['id'] not in ids]
    pets.extend({'id': FIRST_ID + rank - 1, 'name': f'宠物气功弹LV{rank}',
                 'category': 'physical', 'source': 'pet', 'cost': 1000}
                for rank in range(1, 11))
    data['pets'] = pets
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2), 'utf-8')
    runtime = ROOT / 'gmsv/lua/Modules/skillTrainingData.lua'
    raw = runtime.read_bytes()
    newline = '\r\n' if b'\r\n' in raw else '\n'
    runtime.write_bytes(('return ' + lua(data) + newline).encode('gbk'))
    report_path = ROOT / 'docs/skill_training/build_report.json'
    report = json.loads(report_path.read_text('utf-8'))
    from collections import Counter
    report['pets'] = len(pets)
    report['pet_categories'] = dict(Counter(s['category'] for s in pets))
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), 'utf-8')
    print(json.dumps({'added_techs': added, 'pet_qigong_ids': sorted(ids), 'restart_required': True}))


if __name__ == '__main__':
    main()
