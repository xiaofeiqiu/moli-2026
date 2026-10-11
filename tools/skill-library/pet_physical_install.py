"""Complete ordinary pet DoubleEdge / Smash ranks VI-X without replacing I-V."""
from collections import Counter
from pathlib import Path
import json
import sys

from build import lua

ROOT = Path(__file__).resolve().parents[2]
ROMAN = ('Ⅰ', 'Ⅱ', 'Ⅲ', 'Ⅳ', 'Ⅴ', 'Ⅵ', 'Ⅶ', 'Ⅷ', 'Ⅸ', 'Ⅹ')
ASCII = ('I', 'II', 'III', 'IV', 'V', 'VI', 'VII', 'VIII', 'IX', 'X')
# Use free native IDs for native series, and independent copy IDs for imported
# series. Upgrade grouping keeps the original SKILLID and naming convention.
SERIES = (
    (138, 140, '诸刃', ROMAN),
    (338, 340, '乾坤一掷', ROMAN),
    (700033, 910500, '诸刃', ASCII),
    (700051, 910510, '乾坤一掷', ASCII),
)


def install_techs():
    path = ROOT / 'gmsv/data/tech.txt'
    raw = path.read_bytes()
    newline = b'\r\n' if b'\r\n' in raw else b'\n'
    records = {}
    for line in raw.decode('gbk').splitlines():
        row = line.split('\t')
        if len(row) == 15 and row[3].isdigit():
            tid = int(row[3])
            assert tid not in records, f'Duplicate Tech ID: {tid}'
            records[tid] = row
    added, lessons = [], []
    for source_id, first_id, name, suffixes in SERIES:
        source = records[source_id]
        assert source[1] == 'TECH_Parameter' and source[6:9] == ['30', '1', '1141'] and source[12] == '0', source_id
        for rank in range(6, 11):
            row = source.copy()
            tid = first_id + (rank - 6) * (2 if source_id < 700000 else 1)
            row[0], row[3] = name + '-' + suffixes[rank - 1], str(tid)
            if name == '诸刃':
                # I-V lose 10/30/50/70/90% defense. Beyond V, reach zero
                # defense gradually, never extrapolate to negative defense.
                penalty = 90 + 2 * (rank - 5)
                row[2] = f'AS:0,TR:{10 * rank - 5},DR:-{penalty},MR:-{penalty},'
            else:
                row[2] = f'AS:0,HR:-{6 * rank - 3},DD:{20 * rank - 10},'
            row[9], row[11] = str(1000 * (rank - 1) ** 2), str(20 * rank - 10)
            existing = records.get(tid)
            assert existing is None or existing == row, f'Tech ID collision: {tid}'
            if existing is None:
                added.append('\t'.join(row).encode('gbk') + newline)
            lessons.append({'id': tid, 'name': row[0], 'category': 'physical', 'source': 'pet', 'cost': 1000})
    if added:
        backup = ROOT / 'backups/pet_physical_20261011/before/gmsv/data/tech.txt'
        if not backup.exists():
            backup.parent.mkdir(parents=True, exist_ok=True)
            backup.write_bytes(raw)
        path.write_bytes(raw + (b'' if raw.endswith(b'\n') else newline) + b''.join(added))
    return len(added), lessons


def main():
    added, lessons = install_techs()
    path = ROOT / 'docs/skill_training/catalog.json'
    data = json.loads(path.read_text('utf-8'))
    by_id = {s['id']: s for s in lessons}
    # Place VI-X immediately after their V lesson, retaining every older entry.
    data['pets'] = [s for s in data['pets'] if s['id'] not in by_id]
    for index, (source_id, _, _, _) in enumerate(SERIES):
        at = next(i + 1 for i, s in enumerate(data['pets']) if s['id'] == source_id)
        data['pets'][at:at] = lessons[index * 5:(index + 1) * 5]
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2), 'utf-8')
    path = ROOT / 'gmsv/lua/Modules/skillTrainingData.lua'
    newline = '\r\n' if b'\r\n' in path.read_bytes() else '\n'
    path.write_bytes(('return ' + lua(data) + newline).encode('gbk'))
    path = ROOT / 'docs/skill_training/build_report.json'
    report = json.loads(path.read_text('utf-8'))
    report['pets'] = len(data['pets'])
    report['pet_categories'] = dict(Counter(s['category'] for s in data['pets']))
    path.write_text(json.dumps(report, ensure_ascii=False, indent=2), 'utf-8')
    print(json.dumps({'added_techs': added, 'new_pet_physical_ids': sorted(by_id), 'restart_required': True}))


if __name__ == '__main__':
    sys.stdout.reconfigure(encoding='utf-8')
    main()
