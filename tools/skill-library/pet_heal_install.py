"""Install E1 pet healing compatibility without editing DATA or pet saves."""
from pathlib import Path
from collections import Counter
import json
from build import lua

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent


def main():
    rows = {}
    for line in (ROOT / 'gmsv/data/tech.txt').read_bytes().decode('gbk').splitlines():
        r = line.split('\t')
        if len(r) > 12 and r[3].isdigit():
            rows[int(r[3])] = r
    a, b = rows[6350], rows[700826]
    assert a[1] == b[1] == 'TECH_Heal_Magic'
    assert [v for k, v in enumerate(a) if k not in (3, 5)] == [v for k, v in enumerate(b) if k not in (3, 5)]
    runtime = ROOT / 'gmsv/lua/Modules/petSkillTutor.lua'
    source = (HERE / 'petSkillTutor.lua').read_bytes()
    assert (b'\r\n' in source) == (b'\r\n' in runtime.read_bytes())
    runtime.write_bytes(source.decode('utf-8').encode('gbk'))
    catalog = ROOT / 'docs/skill_training/catalog.json'
    data = json.loads(catalog.read_text('utf-8'))
    assert any(s['id'] == 6350 for s in data['pets'])
    data['pets'] = [s for s in data['pets'] if s['id'] != 700826]
    catalog.write_text(json.dumps(data, ensure_ascii=False, indent=2), 'utf-8')
    path = ROOT / 'gmsv/lua/Modules/skillTrainingData.lua'
    newline = '\r\n' if b'\r\n' in path.read_bytes() else '\n'
    path.write_bytes(('return ' + lua(data) + newline).encode('gbk'))
    report = ROOT / 'docs/skill_training/build_report.json'
    summary = json.loads(report.read_text('utf-8'))
    summary['pets'] = len(data['pets'])
    summary['pet_categories'] = dict(Counter(s['category'] for s in data['pets']))
    report.write_text(json.dumps(summary, ensure_ascii=False, indent=2), 'utf-8')
    print('Installed E1 pet healing compatibility; reload petSkillTutor. No DATA/save changes.')


if __name__ == '__main__':
    main()
