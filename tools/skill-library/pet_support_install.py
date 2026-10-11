"""Expose native healing, recovery and revive spells to the pet tutor, LV1-LV10."""
from pathlib import Path
from collections import Counter
import json
from build import lua

ROOT = Path(__file__).resolve().parents[2]
SERIES = {6100: ('补血魔法', 'TECH_Heal_Magic'), 6200: ('强力补血魔法', 'TECH_Heal_Magic'),
          6300: ('超强补血魔法', 'TECH_Heal_Magic'), 6400: ('恢复魔法', 'TECH_LpRecovery'),
          6500: ('强力恢复魔法', 'TECH_LpRecovery'), 6600: ('超强恢复魔法', 'TECH_LpRecovery'),
          6800: ('气绝回复', 'TECH_Revive')}
PET_SUPPORT_NATIVE = {base + offset for base in SERIES for offset in range(10)}


def lesson_name(tid, native_name):
    base = tid - tid % 100
    level = tid - base + 1
    name = SERIES[base][0] + 'LV' + str(level)
    return name if level < 10 else name + '（' + native_name + '）'


def main():
    techs = {int(r[3]): r for line in (ROOT / 'gmsv/data/tech.txt').read_bytes().decode('gbk').splitlines()
             if len(r := line.split('\t')) > 12 and r[3].isdigit()}
    lessons = []
    for base, (_, func) in SERIES.items():
        for offset in range(10):
            tid = base + offset
            row = techs[tid]
            assert row[1] == func and row[6] == str(offset + 1) and row[7] == '1', tid
            target = '87' if base == 6800 else {0: '93', 1: '157', 2: '285'}[(base // 100 - 61) % 3]
            assert row[8] == target, tid
            lessons.append({'id': tid, 'name': lesson_name(tid, row[0]), 'category': 'healing', 'source': 'pet', 'cost': 1000})
    path = ROOT / 'docs/skill_training/catalog.json'
    data = json.loads(path.read_text('utf-8'))
    data['pets'] = [s for s in data['pets'] if s['id'] not in PET_SUPPORT_NATIVE]
    at = next((i for i, s in enumerate(data['pets']) if s['category'] == 'healing'), len(data['pets']))
    data['pets'][at:at] = lessons
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2), 'utf-8')
    path = ROOT / 'gmsv/lua/Modules/skillTrainingData.lua'
    newline = '\r\n' if b'\r\n' in path.read_bytes() else '\n'
    path.write_bytes(('return ' + lua(data) + newline).encode('gbk'))
    path = ROOT / 'docs/skill_training/build_report.json'
    report = json.loads(path.read_text('utf-8'))
    report['pets'] = len(data['pets'])
    report['pet_categories'] = dict(Counter(s['category'] for s in data['pets']))
    path.write_text(json.dumps(report, ensure_ascii=False, indent=2), 'utf-8')
    print('Installed all 70 native pet healing/recovery/revive lessons (seven series, LV1-LV10). No DATA/save changes.')


if __name__ == '__main__':
    main()
