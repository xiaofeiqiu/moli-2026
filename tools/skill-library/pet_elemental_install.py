"""Expose native all-enemy earth/water/fire/wind spells to pets, LV1-LV10."""
from collections import Counter
from pathlib import Path
import json

from build import lua

ROOT = Path(__file__).resolve().parents[2]
SERIES = {2700: '超强陨石魔法', 2800: '超强冰冻魔法',
          2900: '超强火焰魔法', 3000: '超强风刃魔法'}
PET_ELEMENTAL_NATIVE = {base + offset for base in SERIES for offset in range(10)}


def lesson_name(tid, native_name):
    base = tid - tid % 100
    level = tid - base + 1
    name = SERIES[base] + 'LV' + str(level)
    return name if level < 10 else name + '（' + native_name + '）'


def write_preserving_newlines(path, text, encoding='utf-8'):
    raw = path.read_bytes()
    newline = '\r\n' if b'\r\n' in raw else '\n'
    path.write_bytes(text.replace('\r\n', '\n').replace('\n', newline).encode(encoding))


def main():
    techs = {int(r[3]): r for line in (ROOT / 'gmsv/data/tech.txt').read_bytes().decode('gbk').splitlines()
             if len(r := line.split('\t')) > 12 and r[3].isdigit()}
    lessons = []
    for base in SERIES:
        for offset in range(10):
            tid = base + offset
            row = techs[tid]
            assert row[1] == 'TECH_Attack_Magic' and row[6] == str(offset + 1), tid
            assert row[7] == '1' and row[8] == '317' and row[5] == str(base // 100), tid
            assert row[11] == str(40 * (offset + 1)), tid
            lessons.append({'id': tid, 'name': lesson_name(tid, row[0]),
                            'category': 'magic', 'source': 'pet', 'cost': 1000})
    path = ROOT / 'docs/skill_training/catalog.json'
    data = json.loads(path.read_text('utf-8'))
    data['pets'] = [s for s in data['pets'] if s['id'] not in PET_ELEMENTAL_NATIVE]
    # Keep the four series together, immediately after existing pet elemental spells.
    at = next((i for i, s in enumerate(data['pets']) if s['id'] == 2639), None)
    at = at + 1 if at is not None else next(
        (i for i, s in enumerate(data['pets']) if s['category'] == 'magic'), len(data['pets']))
    data['pets'][at:at] = lessons
    write_preserving_newlines(path, json.dumps(data, ensure_ascii=False, indent=2))
    write_preserving_newlines(ROOT / 'gmsv/lua/Modules/skillTrainingData.lua',
                              'return ' + lua(data) + '\n', 'gbk')
    path = ROOT / 'docs/skill_training/build_report.json'
    report = json.loads(path.read_text('utf-8'))
    report['pets'] = len(data['pets'])
    report['pet_categories'] = dict(Counter(s['category'] for s in data['pets']))
    write_preserving_newlines(path, json.dumps(report, ensure_ascii=False, indent=2))
    print('Installed 40 native pet all-enemy elemental lessons (four series, LV1-LV10). '
          'Reload petSkillTutor; no DATA/save changes.')


if __name__ == '__main__':
    main()
