"""Install pet strong bodyguard DATA and lesson, preserving existing line endings."""
from pathlib import Path
from collections import Counter
import json
from build import lua

ROOT = Path(__file__).resolve().parents[2]


def main():
    path = ROOT / 'gmsv/data/tech.txt'
    raw = path.read_bytes()
    newline = '\r\n' if b'\r\n' in raw else '\n'
    text = raw.decode('gbk')
    rows = [line.split('\t') for line in text.splitlines()]
    definitions = {}
    lessons = []
    pet_base = next(r for r in rows if len(r) > 12 and r[3] == '730')
    for level in range(1, 11):
        native, tid = 699 + level, 729 + 2 * level
        base = next(r for r in rows if len(r) > 12 and r[3] == str(native))
        expected = pet_base.copy()
        expected[0], expected[2], expected[3], expected[11] = '强力护卫LV' + str(level), base[2], str(tid), str(int(base[11]) * 4)
        existing = [r for r in rows if len(r) > 3 and r[3] == str(tid)]
        compatible = [expected]
        if level <= 5:
            old = next(r for r in rows if len(r) > 12 and r[3] == str(728 + 2 * level)).copy()
            old[0], old[3], old[11] = '强力护卫-' + ('Ⅰ', 'Ⅱ', 'Ⅲ', 'Ⅳ', 'Ⅴ')[level - 1], str(tid), str(int(old[11]) * 4)
            compatible.append(old)
            if level == 1:
                legacy = old.copy();legacy[0] = '强力护卫';compatible.append(legacy)
        assert not existing or (len(existing) == 1 and existing[0] in compatible), f'Technique {tid} is already occupied'
        definitions[str(tid)] = expected
        lessons.append({'id': tid, 'name': expected[0], 'category': 'physical', 'source': 'pet', 'cost': 1000})
    installed = set()
    output = []
    for line in text.splitlines(keepends=True):
        body = line.rstrip('\r\n');fields = body.split('\t')
        if len(fields) > 3 and fields[3] in definitions:
            installed.add(fields[3]);line = '\t'.join(definitions[fields[3]]) + line[len(body):]
        output.append(line)
    text = ''.join(output)
    for tid, definition in definitions.items():
        if tid not in installed:
            text += ('' if text.endswith('\n') else newline) + '\t'.join(definition) + newline
    path.write_bytes(text.encode('gbk'))
    path = ROOT / 'docs/skill_training/catalog.json'
    data = json.loads(path.read_text('utf-8'))
    data['pets'] = [s for s in data['pets'] if str(s['id']) not in definitions]
    at = next(i for i, s in enumerate(data['pets']) if s['id'] == 730)
    data['pets'][at + 1:at + 1] = lessons
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2), 'utf-8')
    path = ROOT / 'gmsv/lua/Modules/skillTrainingData.lua'
    newline = '\r\n' if b'\r\n' in path.read_bytes() else '\n'
    path.write_bytes(('return ' + lua(data) + newline).encode('gbk'))
    path = ROOT / 'docs/skill_training/build_report.json'
    report = json.loads(path.read_text('utf-8'))
    report['pets'] = len(data['pets'])
    report['pet_categories'] = dict(Counter(s['category'] for s in data['pets']))
    path.write_text(json.dumps(report, ensure_ascii=False, indent=2), 'utf-8')
    for source, runtime in [('tools/skill-library/petSkillTutor.lua', 'gmsv/lua/Modules/petSkillTutor.lua'),
                            ('tools/five-pet/fivePet.lua', 'gmsv/lua/Modules/fivePet.lua')]:
        src, dst = ROOT / source, ROOT / runtime
        newline = '\r\n' if b'\r\n' in dst.read_bytes() else '\n'
        text = src.read_bytes().decode('utf-8').replace('\r\n', '\n')
        src_newline = '\r\n' if b'\r\n' in src.read_bytes() else '\n'
        src.write_bytes(text.replace('\n', src_newline).encode('utf-8'))
        dst.write_bytes(text.replace('\n', newline).encode('gbk'))
    print('Installed strong bodyguard LV1-LV10 (731..749 odd IDs); restart server to load new DATA.')


if __name__ == '__main__':
    main()
